`timescale 1ns/1ps
/*
 * Copyright (c) 2026 shivamtiwari020505
 * SPDX-License-Identifier: Apache-2.0
 */

module apb_slave_if #(
    parameter PRESCALER_RESET = 16'h00C7
) (
    input  wire        PCLK,
    input  wire        PRESETn,
    input  wire        PSEL,
    input  wire        PENABLE,
    input  wire        PWRITE,
    input  wire [7:0]  PADDR,
    input  wire [31:0] PWDATA,
    output reg  [31:0] PRDATA,
    output wire        PREADY,
    output wire        PSLVERR,

    input  wire [31:0] status_i,
    input  wire [7:0]  tx_fifo_data_i,
    input  wire        tx_fifo_empty_i,
    input  wire        tx_fifo_full_i,
    input  wire [7:0]  rx_fifo_data_i,
    input  wire        rx_fifo_empty_i,
    input  wire        rx_fifo_full_i,

    output reg  [3:0]  ctrl_o,
    output reg  [15:0] prescaler_o,
    output reg  [6:0]  slave_addr_o,
    output reg  [6:0]  master_addr_o,
    output reg         tx_fifo_wr_o,
    output reg  [7:0]  tx_fifo_wdata_o,
    output reg         rx_fifo_rd_o,
    output reg         fifo_access_error_o,

    output reg         cmd_start_o,
    output reg         cmd_stop_o,
    output reg         cmd_read_o,
    output reg         cmd_write_o,
    output reg         cmd_rep_start_o,
    output reg         irq_clear_o,
    output reg  [7:0]  irq_clear_mask_o,
    output reg         arst_pulse_o
);

    localparam ADDR_CTRL       = 8'h00;
    localparam ADDR_STATUS     = 8'h04;
    localparam ADDR_PRESCALER  = 8'h08;
    localparam ADDR_TX_DATA    = 8'h0C;
    localparam ADDR_RX_DATA    = 8'h10;
    localparam ADDR_LOCAL_SLAVE_ADDR = 8'h14;
    localparam ADDR_CMD        = 8'h18;
    localparam ADDR_IRQ_CLEAR  = 8'h1C;
    localparam ADDR_MASTER_ADDR = 8'h20;

    wire apb_access = PSEL & PENABLE;
    wire apb_write  = apb_access & PWRITE;
    wire apb_read   = apb_access & ~PWRITE;
    wire valid_addr = (PADDR == ADDR_CTRL)       |
                      (PADDR == ADDR_STATUS)     |
                      (PADDR == ADDR_PRESCALER)  |
                      (PADDR == ADDR_TX_DATA)    |
                      (PADDR == ADDR_RX_DATA)    |
                      (PADDR == ADDR_LOCAL_SLAVE_ADDR) |
                      (PADDR == ADDR_CMD)        |
                      (PADDR == ADDR_IRQ_CLEAR)  |
                      (PADDR == ADDR_MASTER_ADDR);

    wire tx_fifo_overflow  = apb_write & (PADDR == ADDR_TX_DATA) & tx_fifo_full_i;
    wire rx_fifo_underflow = apb_read  & (PADDR == ADDR_RX_DATA) & rx_fifo_empty_i;
    wire apb_error         = apb_access & (~valid_addr | tx_fifo_overflow | rx_fifo_underflow);
    wire unused_pwdata_upper = &{1'b0, PWDATA[31:16], 1'b0};

    assign PREADY = 1'b1;
    assign PSLVERR = apb_error;

    always @(posedge PCLK) begin
        if (!PRESETn) begin
            ctrl_o          <= 4'h0;
            prescaler_o     <= PRESCALER_RESET;
            slave_addr_o    <= 7'h50;
            master_addr_o   <= 7'h50;
            tx_fifo_wr_o     <= 1'b0;
            tx_fifo_wdata_o  <= 8'h00;
            rx_fifo_rd_o     <= 1'b0;
            fifo_access_error_o <= 1'b0;
            cmd_start_o     <= 1'b0;
            cmd_stop_o      <= 1'b0;
            cmd_read_o      <= 1'b0;
            cmd_write_o     <= 1'b0;
            cmd_rep_start_o <= 1'b0;
            irq_clear_o     <= 1'b0;
            irq_clear_mask_o <= 8'h00;
            arst_pulse_o    <= 1'b0;
        end else begin
            cmd_start_o      <= 1'b0;
            cmd_stop_o       <= 1'b0;
            cmd_read_o       <= 1'b0;
            cmd_write_o      <= 1'b0;
            cmd_rep_start_o  <= 1'b0;
            tx_fifo_wr_o     <= 1'b0;
            rx_fifo_rd_o     <= 1'b0;
            fifo_access_error_o <= 1'b0;
            irq_clear_o      <= 1'b0;
            irq_clear_mask_o <= 8'h00;
            arst_pulse_o     <= 1'b0;
            fifo_access_error_o <= apb_error;

            if (apb_write) begin
                case (PADDR)
                    ADDR_CTRL: begin
                        ctrl_o       <= PWDATA[3:0];
                        arst_pulse_o <= PWDATA[4];
                    end
                    ADDR_PRESCALER: begin
                        prescaler_o <= PWDATA[15:0];
                    end
                    ADDR_TX_DATA: begin
                        if (!tx_fifo_full_i) begin
                            tx_fifo_wr_o    <= 1'b1;
                            tx_fifo_wdata_o <= PWDATA[7:0];
                        end
                    end
                    ADDR_LOCAL_SLAVE_ADDR: begin
                        slave_addr_o <= PWDATA[6:0];
                    end
                    ADDR_MASTER_ADDR: begin
                        master_addr_o <= PWDATA[6:0];
                    end
                    ADDR_CMD: begin
                        cmd_start_o     <= PWDATA[0];
                        cmd_stop_o      <= PWDATA[1];
                        cmd_read_o      <= PWDATA[2];
                        cmd_write_o     <= PWDATA[3];
                        cmd_rep_start_o <= PWDATA[4];
                    end
                    ADDR_IRQ_CLEAR: begin
                        irq_clear_o      <= 1'b1;
                        irq_clear_mask_o <= PWDATA[7:0];
                    end
                    default: begin
                    end
                endcase
            end

            if (apb_read && (PADDR == ADDR_RX_DATA) && !rx_fifo_empty_i) begin
                rx_fifo_rd_o <= 1'b1;
            end
        end
    end

    always @(*) begin
        case (PADDR)
            ADDR_CTRL:       PRDATA = {28'h0, ctrl_o};
            ADDR_STATUS:     PRDATA = status_i;
            ADDR_PRESCALER:  PRDATA = {16'h0000, prescaler_o};
            ADDR_TX_DATA:    PRDATA = {22'h000000, tx_fifo_full_i, tx_fifo_empty_i, tx_fifo_data_i};
            ADDR_RX_DATA:    PRDATA = {22'h000000, rx_fifo_full_i, rx_fifo_empty_i, rx_fifo_data_i};
            ADDR_LOCAL_SLAVE_ADDR: PRDATA = {25'h0000000, slave_addr_o};
            ADDR_CMD:        PRDATA = 32'h00000000;
            ADDR_IRQ_CLEAR:  PRDATA = 32'h00000000;
            ADDR_MASTER_ADDR: PRDATA = {25'h0000000, master_addr_o};
            default:         PRDATA = 32'h00000000;
        endcase
    end

endmodule
