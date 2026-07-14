`timescale 1ns/1ps
/*
 * Copyright (c) 2026 shivamtiwari020505
 * SPDX-License-Identifier: Apache-2.0
 */

module i2c_top_split_io #(
    parameter CLK_FREQ_HZ          = 50000000,
    parameter I2C_FREQ_HZ          = 400000,
    parameter ADDR_BITS            = 7,
    parameter REG_DATA_WIDTH       = 8,
    parameter NUM_REGS             = 16,
    parameter FIFO_DEPTH           = 8,
    parameter REG_ADDR_WIDTH       = 4,
    parameter SLAVE_STRETCH_CYCLES = 16,
    parameter TIMEOUT_CYCLES       = 256,
    parameter INPUT_SYNC_STAGES    = 2,
    parameter INPUT_FILTER_LEN     = 1
) (
    input  wire        PCLK,
    input  wire        PRESETn,
    input  wire        PSEL,
    input  wire        PENABLE,
    input  wire        PWRITE,
    input  wire [7:0]  PADDR,
    input  wire [31:0] PWDATA,
    output wire [31:0] PRDATA,
    output wire        PREADY,
    output wire        PSLVERR,
    output wire        IRQ,
    input  wire        sda_i,
    input  wire        scl_i,
    output wire        sda_o,
    output wire        sda_oe,
    output wire        scl_o,
    output wire        scl_oe
);

    function integer clog2;
        input integer value;
        integer i;
        begin
            clog2 = 0;
            for (i = value - 1; i > 0; i = i >> 1) begin
                clog2 = clog2 + 1;
            end
        end
    endfunction

    function integer ceil_div;
        input integer num;
        input integer den;
        begin
            ceil_div = (num + den - 1) / den;
        end
    endfunction

    function integer max_int;
        input integer a;
        input integer b;
        begin
            max_int = (a > b) ? a : b;
        end
    endfunction

    function integer t_low_ns_for_freq;
        input integer freq_hz;
        begin
            if (freq_hz <= 100000)
                t_low_ns_for_freq = 4700;
            else if (freq_hz <= 400000)
                t_low_ns_for_freq = 1300;
            else
                t_low_ns_for_freq = 500;
        end
    endfunction

    function integer ns_to_cycles;
        input integer clk_hz;
        input integer ns;
        integer clk_khz;
        begin
            clk_khz = ceil_div(clk_hz, 1000);
            ns_to_cycles = ceil_div(clk_khz * ns, 1000000);
        end
    endfunction

    function [15:0] prescaler_from_cycles;
        input integer cycles;
        begin
            if (cycles <= 1)
                prescaler_from_cycles = 16'h0000;
            else if (cycles > 65536)
                prescaler_from_cycles = 16'hFFFF;
            else
                prescaler_from_cycles = cycles[15:0] - 16'd1;
        end
    endfunction

    localparam FIFO_ADDR_WIDTH = clog2(FIFO_DEPTH);
    localparam integer TARGET_HALF_CYCLES = ceil_div(CLK_FREQ_HZ, (2 * I2C_FREQ_HZ));
    localparam integer TLOW_CYCLES = ns_to_cycles(CLK_FREQ_HZ, t_low_ns_for_freq(I2C_FREQ_HZ));
    localparam integer DEFAULT_HALF_CYCLES = max_int(TARGET_HALF_CYCLES, TLOW_CYCLES);
    localparam [15:0] PRESCALER_RESET_VALUE = prescaler_from_cycles(DEFAULT_HALF_CYCLES);

// synthesis translate_off
    initial begin
        if (ADDR_BITS != 7) begin
            $display("ERROR: i2c_top_split_io only supports ADDR_BITS=7 in this release.");
            $finish;
        end
        if (REG_DATA_WIDTH != 8) begin
            $display("ERROR: i2c_top_split_io only supports REG_DATA_WIDTH=8 in this release.");
            $finish;
        end
        if (FIFO_DEPTH < 2) begin
            $display("ERROR: i2c_top_split_io requires FIFO_DEPTH >= 2.");
            $finish;
        end
        if (INPUT_SYNC_STAGES < 1) begin
            $display("ERROR: i2c_top_split_io requires INPUT_SYNC_STAGES >= 1.");
            $finish;
        end
        if (INPUT_FILTER_LEN < 1) begin
            $display("ERROR: i2c_top_split_io requires INPUT_FILTER_LEN >= 1.");
            $finish;
        end
    end
// synthesis translate_on

    wire [3:0]  ctrl;
    wire [15:0] prescaler;
    wire [6:0]  slave_addr;
    wire [6:0]  master_addr;
    wire        cmd_start;
    wire        cmd_stop;
    wire        cmd_read;
    wire        cmd_write;
    wire        cmd_rep_start;
    wire        irq_clear;
    wire [7:0]  irq_clear_mask;
    wire        arst_pulse;
    wire        tx_fifo_wr;
    wire [7:0]  tx_fifo_wdata;
    wire        rx_fifo_rd;
    wire        fifo_access_error;

    wire core_en   = ctrl[0];
    wire master_en = ctrl[1];
    wire slave_en  = ctrl[2];
    wire irq_en    = ctrl[3];
    wire local_resetn = PRESETn & ~arst_pulse;

    wire div_tick;
    wire sda_raw_in;
    wire scl_raw_in;
    wire sda_in;
    wire scl_in;
    wire master_sda_drive;
    wire master_scl_drive;
    wire slave_sda_drive;
    wire slave_scl_drive;

    wire [7:0] master_rx_data;
    wire       master_rx_valid_pulse;
    wire       master_ack_rx;
    wire       master_arb_lost_pulse;
    wire       master_error_pulse;
    wire       master_bus_active;
    wire       master_busy;
    wire       master_ack_sample_phase_unused;
    wire       master_ack_phase_unused;
    wire [3:0] master_state;

    wire [7:0] tx_fifo_data;
    wire       tx_fifo_empty;
    wire       tx_fifo_full;
    wire [FIFO_ADDR_WIDTH:0] tx_fifo_count_unused;
    wire       tx_fifo_rd;

    wire [7:0] rx_fifo_data;
    wire       rx_fifo_empty;
    wire       rx_fifo_full;
    wire [FIFO_ADDR_WIDTH:0] rx_fifo_count_unused;
    wire       rx_fifo_wr;

    wire reg_wr_en;
    wire [REG_ADDR_WIDTH-1:0] reg_wr_addr;
    wire [REG_DATA_WIDTH-1:0] reg_wr_data;
    wire [REG_ADDR_WIDTH-1:0] reg_rd_addr;
    wire [REG_DATA_WIDTH-1:0] reg_rd_data;
    wire slave_stretch_active_unused;
    wire slave_addr_match_pulse_unused;
    wire slave_rx_done_pulse_unused;
    wire slave_tx_done_pulse_unused;
    wire [2:0] slave_state;

    reg       ack_rx_reg;
    reg       arb_lost_reg;
    reg       error_reg;
    reg       irq_reg;

    wire unused_debug_outputs = &{
        1'b0,
        master_ack_sample_phase_unused,
        master_ack_phase_unused,
        tx_fifo_count_unused,
        rx_fifo_count_unused,
        slave_stretch_active_unused,
        slave_addr_match_pulse_unused,
        slave_rx_done_pulse_unused,
        slave_tx_done_pulse_unused,
        1'b0
    };

    wire fifo_cmd_underflow = cmd_write & tx_fifo_empty;
    wire cmd_blocked_by_fifo = fifo_cmd_underflow;
    wire master_cmd_start = cmd_blocked_by_fifo ? 1'b0 : cmd_start;
    wire master_cmd_stop = cmd_blocked_by_fifo ? 1'b0 : cmd_stop;
    wire master_cmd_read = cmd_blocked_by_fifo ? 1'b0 : cmd_read;
    wire master_cmd_write = cmd_blocked_by_fifo ? 1'b0 : cmd_write;
    wire master_cmd_rep_start = cmd_blocked_by_fifo ? 1'b0 : cmd_rep_start;
    wire master_accepts_write_cmd = master_cmd_write &
                                    (master_state == 4'h0) &
                                    ((master_cmd_start | master_cmd_rep_start) | master_bus_active);

    assign tx_fifo_rd = master_accepts_write_cmd;
    assign rx_fifo_wr = master_rx_valid_pulse & ~rx_fifo_full;

    wire tx_empty = core_en ? tx_fifo_empty : 1'b0;
    wire rx_valid = ~rx_fifo_empty;
    wire bus_busy = master_busy | master_bus_active | (slave_state != 3'h0) |
                    (scl_in == 1'b0) | (sda_in == 1'b0);

    wire [31:0] status_word = {
        24'h000000,
        error_reg,
        rx_fifo_full,
        tx_fifo_full,
        rx_valid,
        tx_empty,
        arb_lost_reg,
        ack_rx_reg,
        bus_busy
    };

    apb_slave_if #(
        .PRESCALER_RESET(PRESCALER_RESET_VALUE)
    ) u_apb_slave_if (
        .PCLK(PCLK),
        .PRESETn(PRESETn),
        .PSEL(PSEL),
        .PENABLE(PENABLE),
        .PWRITE(PWRITE),
        .PADDR(PADDR),
        .PWDATA(PWDATA),
        .PRDATA(PRDATA),
        .PREADY(PREADY),
        .PSLVERR(PSLVERR),
        .status_i(status_word),
        .tx_fifo_data_i(tx_fifo_data),
        .tx_fifo_empty_i(tx_fifo_empty),
        .tx_fifo_full_i(tx_fifo_full),
        .rx_fifo_data_i(rx_fifo_data),
        .rx_fifo_empty_i(rx_fifo_empty),
        .rx_fifo_full_i(rx_fifo_full),
        .ctrl_o(ctrl),
        .prescaler_o(prescaler),
        .slave_addr_o(slave_addr),
        .master_addr_o(master_addr),
        .tx_fifo_wr_o(tx_fifo_wr),
        .tx_fifo_wdata_o(tx_fifo_wdata),
        .rx_fifo_rd_o(rx_fifo_rd),
        .fifo_access_error_o(fifo_access_error),
        .cmd_start_o(cmd_start),
        .cmd_stop_o(cmd_stop),
        .cmd_read_o(cmd_read),
        .cmd_write_o(cmd_write),
        .cmd_rep_start_o(cmd_rep_start),
        .irq_clear_o(irq_clear),
        .irq_clear_mask_o(irq_clear_mask),
        .arst_pulse_o(arst_pulse)
    );

    clk_divider u_clk_divider (
        .clk(PCLK),
        .resetn(local_resetn),
        .enable(core_en & master_en),
        .prescaler(prescaler),
        .tick(div_tick)
    );

    i2c_line_filter #(
        .SYNC_STAGES(INPUT_SYNC_STAGES),
        .FILTER_LEN(INPUT_FILTER_LEN)
    ) u_i2c_line_filter (
        .clk(PCLK),
        .resetn(local_resetn),
        .raw_sda(sda_raw_in),
        .raw_scl(scl_raw_in),
        .sda_out(sda_in),
        .scl_out(scl_in)
    );

    i2c_master_fsm #(
        .TIMEOUT_CYCLES(TIMEOUT_CYCLES)
    ) u_master (
        .clk(PCLK),
        .resetn(local_resetn),
        .enable(core_en & master_en),
        .tick(div_tick),
        .cmd_start(master_cmd_start),
        .cmd_stop(master_cmd_stop),
        .cmd_read(master_cmd_read),
        .cmd_write(master_cmd_write),
        .cmd_rep_start(master_cmd_rep_start),
        .tx_data(tx_fifo_data),
        .target_addr(master_addr),
        .sda_in(sda_in),
        .scl_in(scl_in),
        .sda_drive(master_sda_drive),
        .scl_drive(master_scl_drive),
        .rx_data(master_rx_data),
        .rx_valid_pulse(master_rx_valid_pulse),
        .ack_rx(master_ack_rx),
        .arb_lost_pulse(master_arb_lost_pulse),
        .error_pulse(master_error_pulse),
        .bus_active(master_bus_active),
        .busy(master_busy),
        .ack_sample_phase(master_ack_sample_phase_unused),
        .master_ack_phase(master_ack_phase_unused),
        .state(master_state)
    );

    sync_fifo #(
        .DATA_WIDTH(8),
        .DEPTH(FIFO_DEPTH),
        .ADDR_WIDTH(FIFO_ADDR_WIDTH)
    ) u_tx_fifo (
        .clk(PCLK),
        .resetn(local_resetn),
        .clear(arst_pulse),
        .wr_en(tx_fifo_wr),
        .wr_data(tx_fifo_wdata),
        .rd_en(tx_fifo_rd),
        .rd_data(tx_fifo_data),
        .empty(tx_fifo_empty),
        .full(tx_fifo_full),
        .count(tx_fifo_count_unused)
    );

    sync_fifo #(
        .DATA_WIDTH(8),
        .DEPTH(FIFO_DEPTH),
        .ADDR_WIDTH(FIFO_ADDR_WIDTH)
    ) u_rx_fifo (
        .clk(PCLK),
        .resetn(local_resetn),
        .clear(arst_pulse),
        .wr_en(rx_fifo_wr),
        .wr_data(master_rx_data),
        .rd_en(rx_fifo_rd),
        .rd_data(rx_fifo_data),
        .empty(rx_fifo_empty),
        .full(rx_fifo_full),
        .count(rx_fifo_count_unused)
    );

    reg_file #(
        .DATA_WIDTH(REG_DATA_WIDTH),
        .NUM_REGS(NUM_REGS),
        .ADDR_WIDTH(REG_ADDR_WIDTH)
    ) u_reg_file (
        .clk(PCLK),
        .resetn(local_resetn),
        .wr_en(reg_wr_en),
        .wr_addr(reg_wr_addr),
        .wr_data(reg_wr_data),
        .rd_addr(reg_rd_addr),
        .rd_data(reg_rd_data)
    );

    i2c_slave_fsm #(
        .NUM_REGS(NUM_REGS),
        .REG_ADDR_WIDTH(REG_ADDR_WIDTH),
        .STRETCH_CYCLES(SLAVE_STRETCH_CYCLES)
    ) u_slave (
        .clk(PCLK),
        .resetn(local_resetn),
        .enable(core_en & slave_en),
        .slave_addr(slave_addr),
        .sda_in(sda_in),
        .scl_in(scl_in),
        .sda_drive(slave_sda_drive),
        .scl_drive(slave_scl_drive),
        .reg_wr_en(reg_wr_en),
        .reg_wr_addr(reg_wr_addr),
        .reg_wr_data(reg_wr_data),
        .reg_rd_addr(reg_rd_addr),
        .reg_rd_data(reg_rd_data),
        .stretch_active(slave_stretch_active_unused),
        .address_match_pulse(slave_addr_match_pulse_unused),
        .rx_done_pulse(slave_rx_done_pulse_unused),
        .tx_done_pulse(slave_tx_done_pulse_unused),
        .state(slave_state)
    );

    wire sda_pull_low = master_sda_drive | slave_sda_drive;
    wire scl_pull_low = master_scl_drive | slave_scl_drive;

    assign sda_o  = 1'b0;
    assign scl_o  = 1'b0;
    assign sda_oe = sda_pull_low;
    assign scl_oe = scl_pull_low;
    assign sda_raw_in = sda_i;
    assign scl_raw_in = scl_i;

    always @(posedge PCLK) begin
        if (!PRESETn || arst_pulse) begin
            ack_rx_reg   <= 1'b0;
            arb_lost_reg <= 1'b0;
            error_reg    <= 1'b0;
            irq_reg      <= 1'b0;
        end else begin
            if (master_ack_rx) begin
                ack_rx_reg <= 1'b1;
            end

            if (master_arb_lost_pulse) begin
                arb_lost_reg <= 1'b1;
            end

            if (master_error_pulse | fifo_access_error | fifo_cmd_underflow | (master_rx_valid_pulse & rx_fifo_full)) begin
                error_reg <= 1'b1;
            end

            if (irq_clear) begin
                if (irq_clear_mask[1]) ack_rx_reg   <= 1'b0;
                if (irq_clear_mask[2]) arb_lost_reg <= 1'b0;
                if (irq_clear_mask[7]) error_reg    <= 1'b0;
            end

            if (!irq_en) begin
                irq_reg <= 1'b0;
            end else if (master_rx_valid_pulse | master_arb_lost_pulse | master_error_pulse |
                         fifo_access_error | fifo_cmd_underflow | (master_rx_valid_pulse & rx_fifo_full)) begin
                irq_reg <= 1'b1;
            end else if (irq_clear) begin
                irq_reg <= |(status_word[7:0] & ~irq_clear_mask);
            end
        end
    end

    assign IRQ = irq_reg;

endmodule

// Repository status refresh: 2026-07-14
