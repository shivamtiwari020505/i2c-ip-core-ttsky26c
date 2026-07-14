`timescale 1ns/1ps
/*
 * Copyright (c) 2026 shivamtiwari020505
 * SPDX-License-Identifier: Apache-2.0
 */
`default_nettype none

module tt_um_shivamtiwari020505_i2c (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    localparam ADDR_CTRL       = 8'h00;
    localparam ADDR_STATUS     = 8'h04;
    localparam ADDR_TX_DATA    = 8'h0C;
    localparam ADDR_RX_DATA    = 8'h10;
    localparam ADDR_LOCAL_ADDR = 8'h14;
    localparam ADDR_CMD        = 8'h18;
    localparam ADDR_IRQ_CLEAR  = 8'h1C;
    localparam ADDR_MASTER_ADDR = 8'h20;

    localparam CTRL_CORE_EN   = 32'h00000001;
    localparam CTRL_MASTER_EN = 32'h00000002;
    localparam CTRL_SLAVE_EN  = 32'h00000004;
    localparam CTRL_IRQ_EN    = 32'h00000008;

    localparam ST_IDLE   = 2'd0;
    localparam ST_SETUP  = 2'd1;
    localparam ST_ACCESS = 2'd2;

    reg [1:0] apb_state;
    reg       apb_psel;
    reg       apb_penable;
    reg       apb_pwrite;
    reg [7:0] apb_paddr;
    reg [31:0] apb_pwdata;
    reg       apb_read_pending;

    reg [1:0] init_step;
    reg       init_done;
    reg [3:2] uio_strobe_q;
    reg       irq_clear_q;
    reg [7:0] out_reg;
    reg       last_pslverr;

    wire [31:0] apb_prdata;
    wire        apb_pready;
    wire        apb_pslverr;
    wire        irq;
    wire        core_resetn = rst_n & ena;

    wire sda_o;
    wire sda_oe;
    wire scl_o;
    wire scl_oe;

    wire wr_strobe_rise = ena & init_done & uio_in[2] & ~uio_strobe_q[2];
    wire rd_strobe_rise = ena & init_done & uio_in[3] & ~uio_strobe_q[3];
    wire irq_clear_rise = ena & init_done & uio_in[6] & ~irq_clear_q;
    wire reg_sel        = uio_in[4];

    i2c_top_split_io #(
        .CLK_FREQ_HZ(50000000),
        .I2C_FREQ_HZ(400000),
        .ADDR_BITS(7),
        .REG_DATA_WIDTH(8),
        .NUM_REGS(16),
        .FIFO_DEPTH(8),
        .REG_ADDR_WIDTH(4),
        .SLAVE_STRETCH_CYCLES(16),
        .TIMEOUT_CYCLES(512),
        .INPUT_SYNC_STAGES(2),
        .INPUT_FILTER_LEN(1)
    ) u_core (
        .PCLK(clk),
        .PRESETn(core_resetn),
        .PSEL(apb_psel),
        .PENABLE(apb_penable),
        .PWRITE(apb_pwrite),
        .PADDR(apb_paddr),
        .PWDATA(apb_pwdata),
        .PRDATA(apb_prdata),
        .PREADY(apb_pready),
        .PSLVERR(apb_pslverr),
        .IRQ(irq),
        .sda_i(uio_in[0]),
        .scl_i(uio_in[1]),
        .sda_o(sda_o),
        .sda_oe(sda_oe),
        .scl_o(scl_o),
        .scl_oe(scl_oe)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            apb_state        <= ST_IDLE;
            apb_psel         <= 1'b0;
            apb_penable      <= 1'b0;
            apb_pwrite       <= 1'b0;
            apb_paddr        <= 8'h00;
            apb_pwdata       <= 32'h00000000;
            apb_read_pending <= 1'b0;
            init_step        <= 2'd0;
            init_done        <= 1'b0;
            uio_strobe_q     <= 2'b00;
            irq_clear_q      <= 1'b0;
            out_reg          <= 8'h00;
            last_pslverr     <= 1'b0;
        end else begin
            uio_strobe_q <= uio_in[3:2];
            irq_clear_q  <= uio_in[6];

            if (!ena) begin
                apb_state        <= ST_IDLE;
                apb_psel         <= 1'b0;
                apb_penable      <= 1'b0;
                apb_pwrite       <= 1'b0;
                apb_read_pending <= 1'b0;
                init_step        <= 2'd0;
                init_done        <= 1'b0;
                irq_clear_q      <= 1'b0;
                out_reg          <= 8'h00;
                last_pslverr     <= 1'b0;
            end else begin
                case (apb_state)
                    ST_IDLE: begin
                        apb_psel    <= 1'b0;
                        apb_penable <= 1'b0;
                        last_pslverr <= 1'b0;

                        if (!init_done) begin
                            apb_psel         <= 1'b1;
                            apb_penable      <= 1'b0;
                            apb_pwrite       <= 1'b1;
                            apb_read_pending <= 1'b0;
                            case (init_step)
                                2'd0: begin
                                    apb_paddr  <= ADDR_LOCAL_ADDR;
                                    apb_pwdata <= 32'h00000052;
                                end
                                2'd1: begin
                                    apb_paddr  <= ADDR_MASTER_ADDR;
                                    apb_pwdata <= 32'h00000050;
                                end
                                default: begin
                                    apb_paddr  <= ADDR_CTRL;
                                    apb_pwdata <= CTRL_CORE_EN | CTRL_MASTER_EN | CTRL_SLAVE_EN | CTRL_IRQ_EN;
                                end
                            endcase
                            apb_state <= ST_SETUP;
                        end else if (wr_strobe_rise) begin
                            apb_psel         <= 1'b1;
                            apb_penable      <= 1'b0;
                            apb_pwrite       <= 1'b1;
                            apb_paddr        <= reg_sel ? ADDR_CMD : ADDR_TX_DATA;
                            apb_pwdata       <= {24'h000000, ui_in};
                            apb_read_pending <= 1'b0;
                            apb_state        <= ST_SETUP;
                        end else if (rd_strobe_rise) begin
                            apb_psel         <= 1'b1;
                            apb_penable      <= 1'b0;
                            apb_pwrite       <= 1'b0;
                            apb_paddr        <= reg_sel ? ADDR_STATUS : ADDR_RX_DATA;
                            apb_pwdata       <= 32'h00000000;
                            apb_read_pending <= 1'b1;
                            apb_state        <= ST_SETUP;
                        end else if (irq_clear_rise) begin
                            apb_psel         <= 1'b1;
                            apb_penable      <= 1'b0;
                            apb_pwrite       <= 1'b1;
                            apb_paddr        <= ADDR_IRQ_CLEAR;
                            apb_pwdata       <= 32'h000000FF;
                            apb_read_pending <= 1'b0;
                            apb_state        <= ST_SETUP;
                        end
                    end

                    ST_SETUP: begin
                        apb_penable <= 1'b1;
                        apb_state   <= ST_ACCESS;
                    end

                    ST_ACCESS: begin
                        if (apb_pready) begin
                            if (apb_read_pending) begin
                                out_reg <= apb_prdata[7:0];
                            end
                            last_pslverr     <= apb_pslverr;
                            apb_psel         <= 1'b0;
                            apb_penable      <= 1'b0;
                            apb_pwrite       <= 1'b0;
                            apb_read_pending <= 1'b0;
                            apb_state        <= ST_IDLE;

                            if (!init_done) begin
                                if (init_step == 2'd2) begin
                                    init_done <= 1'b1;
                                end else begin
                                    init_step <= init_step + 2'd1;
                                end
                            end
                        end
                    end

                    default: begin
                        apb_state        <= ST_IDLE;
                        apb_psel         <= 1'b0;
                        apb_penable      <= 1'b0;
                        apb_pwrite       <= 1'b0;
                        apb_read_pending <= 1'b0;
                    end
                endcase
            end
        end
    end

    assign uo_out = out_reg;

    assign uio_out[0] = sda_o;
    assign uio_out[1] = scl_o;
    assign uio_out[2] = 1'b0;
    assign uio_out[3] = 1'b0;
    assign uio_out[4] = 1'b0;
    assign uio_out[5] = irq;
    assign uio_out[6] = 1'b0;
    assign uio_out[7] = last_pslverr;

    assign uio_oe[0] = ena & sda_oe;
    assign uio_oe[1] = ena & scl_oe;
    assign uio_oe[2] = 1'b0;
    assign uio_oe[3] = 1'b0;
    assign uio_oe[4] = 1'b0;
    assign uio_oe[5] = ena;
    assign uio_oe[6] = 1'b0;
    assign uio_oe[7] = ena;

    wire _unused = &{apb_prdata[31:8], uio_in[7], uio_in[5], 1'b0};

endmodule

`default_nettype wire

// Repository status refresh: 2026-07-14
