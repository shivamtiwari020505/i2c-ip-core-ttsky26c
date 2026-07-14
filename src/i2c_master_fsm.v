`timescale 1ns/1ps
/*
 * Copyright (c) 2026 shivamtiwari020505
 * SPDX-License-Identifier: Apache-2.0
 */

module i2c_master_fsm #(
    parameter TIMEOUT_CYCLES = 256
) (
    input  wire       clk,
    input  wire       resetn,
    input  wire       enable,
    input  wire       tick,
    input  wire       cmd_start,
    input  wire       cmd_stop,
    input  wire       cmd_read,
    input  wire       cmd_write,
    input  wire       cmd_rep_start,
    input  wire [7:0] tx_data,
    input  wire [6:0] target_addr,
    input  wire       sda_in,
    input  wire       scl_in,
    output reg        sda_drive,
    output reg        scl_drive,
    output reg  [7:0] rx_data,
    output reg        rx_valid_pulse,
    output reg        ack_rx,
    output reg        arb_lost_pulse,
    output reg        error_pulse,
    output reg        bus_active,
    output wire       busy,
    output reg        ack_sample_phase,
    output reg        master_ack_phase,
    output reg  [3:0] state
);

    localparam IDLE          = 4'h0;
    localparam GEN_START     = 4'h1;
    localparam SCL_LOW_START = 4'h2;
    localparam SEND_ADDR     = 4'h3;
    localparam SEND_RW       = 4'h4;
    localparam WAIT_ACK      = 4'h5;
    localparam SEND_DATA     = 4'h6;
    localparam READ_DATA     = 4'h7;
    localparam SEND_ACK      = 4'h8;
    localparam GEN_STOP      = 4'h9;
    localparam GEN_REP_START = 4'hA;
    localparam ARB_LOST      = 4'hB;
    localparam ERROR         = 4'hC;
    localparam [15:0] TIMEOUT_LIMIT = TIMEOUT_CYCLES;

    localparam ACK_ADDR = 1'b0;
    localparam ACK_DATA = 1'b1;

    reg [1:0] phase;
    reg [3:0] bit_cnt;
    reg [7:0] tx_shift;
    reg [7:1] rx_shift;
    reg       rw_latched;
    reg       stop_latched;
    reg       write_latched;
    reg       ack_context;
    reg [15:0] timeout_count;
    wire [2:0] bit_idx = bit_cnt[2:0];

    assign busy = (state != IDLE) | bus_active;

    function [0:0] drive_for_bit;
        input bit_value;
        begin
            drive_for_bit = ~bit_value;
        end
    endfunction

    always @(posedge clk) begin
        if (!resetn) begin
            state            <= IDLE;
            phase            <= 2'd0;
            bit_cnt          <= 4'd0;
            tx_shift         <= 8'h00;
            rx_shift         <= 7'h00;
            rx_data          <= 8'h00;
            rw_latched       <= 1'b0;
            stop_latched     <= 1'b0;
            write_latched    <= 1'b0;
            ack_context      <= ACK_ADDR;
            timeout_count    <= 16'h0000;
            sda_drive        <= 1'b0;
            scl_drive        <= 1'b0;
            rx_valid_pulse   <= 1'b0;
            ack_rx           <= 1'b0;
            arb_lost_pulse   <= 1'b0;
            error_pulse      <= 1'b0;
            bus_active       <= 1'b0;
            ack_sample_phase <= 1'b0;
            master_ack_phase <= 1'b0;
        end else begin
            rx_valid_pulse   <= 1'b0;
            arb_lost_pulse   <= 1'b0;
            error_pulse      <= 1'b0;
            ack_sample_phase <= 1'b0;
            master_ack_phase <= 1'b0;

            if (!enable) begin
                state         <= IDLE;
                phase         <= 2'd0;
                sda_drive     <= 1'b0;
                scl_drive     <= 1'b0;
                bus_active    <= 1'b0;
                timeout_count <= 16'h0000;
            end else begin
                case (state)
                    IDLE: begin
                        phase         <= 2'd0;
                        timeout_count <= 16'h0000;
                        sda_drive     <= 1'b0;
                        scl_drive     <= bus_active;

                        if ((cmd_start | cmd_rep_start) & !bus_active & (!sda_in | !scl_in)) begin
                            error_pulse   <= 1'b1;
                            stop_latched  <= 1'b0;
                            state         <= ERROR;
                            phase         <= 2'd0;
                        end else if (cmd_start | cmd_rep_start) begin
                            rw_latched    <= cmd_read;
                            write_latched <= cmd_write;
                            stop_latched  <= cmd_stop;
                            tx_shift      <= tx_data;
                            bit_cnt       <= 4'd6;
                            state         <= (cmd_rep_start | bus_active) ? GEN_REP_START : GEN_START;
                            phase         <= 2'd0;
                        end else if (bus_active & cmd_write) begin
                            rw_latched    <= 1'b0;
                            write_latched <= 1'b1;
                            stop_latched  <= cmd_stop;
                            tx_shift      <= tx_data;
                            bit_cnt       <= 4'd7;
                            ack_context   <= ACK_DATA;
                            state         <= SEND_DATA;
                            phase         <= 2'd0;
                        end else if (bus_active & cmd_read) begin
                            rw_latched   <= 1'b1;
                            stop_latched <= cmd_stop;
                            bit_cnt      <= 4'd7;
                            rx_shift     <= 7'h00;
                            state        <= READ_DATA;
                            phase        <= 2'd0;
                        end else if (bus_active & cmd_stop) begin
                            state <= GEN_STOP;
                            phase <= 2'd0;
                        end
                    end

                    GEN_START: begin
                        scl_drive <= 1'b0;
                        case (phase)
                            2'd0: begin
                                sda_drive <= 1'b0;
                                if (tick && scl_in) begin
                                    sda_drive <= 1'b1;
                                    phase     <= 2'd1;
                                end
                            end
                            default: begin
                                if (tick) begin
                                    scl_drive <= 1'b1;
                                    state     <= SCL_LOW_START;
                                    phase     <= 2'd0;
                                end
                            end
                        endcase
                    end

                    GEN_REP_START: begin
                        case (phase)
                            2'd0: begin
                                sda_drive <= 1'b0;
                                scl_drive <= 1'b1;
                                if (tick) phase <= 2'd1;
                            end
                            2'd1: begin
                                scl_drive <= 1'b0;
                                if (scl_in) timeout_count <= 16'h0000;
                                else if (timeout_count < TIMEOUT_LIMIT) timeout_count <= timeout_count + 16'h0001;

                                if (scl_in && tick) begin
                                    sda_drive <= 1'b1;
                                    phase     <= 2'd2;
                                end else if (timeout_count >= TIMEOUT_LIMIT) begin
                                    error_pulse <= 1'b1;
                                    state       <= ERROR;
                                    phase       <= 2'd0;
                                end
                            end
                            default: begin
                                if (tick) begin
                                    scl_drive <= 1'b1;
                                    state     <= SCL_LOW_START;
                                    phase     <= 2'd0;
                                end
                            end
                        endcase
                    end

                    SCL_LOW_START: begin
                        sda_drive <= 1'b1;
                        scl_drive <= 1'b1;
                        if (tick) begin
                            bit_cnt <= 4'd6;
                            state   <= SEND_ADDR;
                            phase   <= 2'd0;
                        end
                    end

                    SEND_ADDR: begin
                        case (phase)
                            2'd0: begin
                                scl_drive <= 1'b1;
                                sda_drive <= drive_for_bit(target_addr[bit_idx]);
                                if (tick) begin
                                    scl_drive <= 1'b0;
                                    phase     <= 2'd1;
                                end
                            end
                            default: begin
                                scl_drive <= 1'b0;
                                if (scl_in && target_addr[bit_idx] && !sda_in) begin
                                    arb_lost_pulse <= 1'b1;
                                    state          <= ARB_LOST;
                                    phase          <= 2'd0;
                                end else if (scl_in && tick) begin
                                    scl_drive <= 1'b1;
                                    phase     <= 2'd0;
                                    if (bit_cnt == 4'd0) begin
                                        state <= SEND_RW;
                                    end else begin
                                        bit_cnt <= bit_cnt - 4'd1;
                                    end
                                end
                            end
                        endcase
                    end

                    SEND_RW: begin
                        case (phase)
                            2'd0: begin
                                scl_drive <= 1'b1;
                                sda_drive <= drive_for_bit(rw_latched);
                                if (tick) begin
                                    scl_drive <= 1'b0;
                                    phase     <= 2'd1;
                                end
                            end
                            default: begin
                                scl_drive <= 1'b0;
                                if (scl_in && rw_latched && !sda_in) begin
                                    arb_lost_pulse <= 1'b1;
                                    state          <= ARB_LOST;
                                    phase          <= 2'd0;
                                end else if (scl_in && tick) begin
                                    scl_drive   <= 1'b1;
                                    sda_drive   <= 1'b0;
                                    ack_context <= ACK_ADDR;
                                    state       <= WAIT_ACK;
                                    phase       <= 2'd0;
                                end
                            end
                        endcase
                    end

                    WAIT_ACK: begin
                        sda_drive        <= 1'b0;
                        ack_sample_phase <= 1'b1;
                        case (phase)
                            2'd0: begin
                                scl_drive <= 1'b1;
                                if (tick) begin
                                    scl_drive     <= 1'b0;
                                    timeout_count <= 16'h0000;
                                    phase         <= 2'd1;
                                end
                            end
                            default: begin
                                scl_drive <= 1'b0;
                                if (scl_in) timeout_count <= 16'h0000;
                                else if (timeout_count < TIMEOUT_LIMIT) timeout_count <= timeout_count + 16'h0001;

                                if (scl_in && tick) begin
                                    ack_rx    <= ~sda_in;
                                    scl_drive <= 1'b1;
                                    phase     <= 2'd0;
                                    if (sda_in) begin
                                        error_pulse <= 1'b1;
                                        state       <= ERROR;
                                    end else if (ack_context == ACK_ADDR) begin
                                        bus_active <= 1'b1;
                                        if (rw_latched) begin
                                            bit_cnt  <= 4'd7;
                            rx_shift <= 7'h00;
                                            state    <= READ_DATA;
                                        end else if (write_latched) begin
                                            bit_cnt <= 4'd7;
                                            state   <= SEND_DATA;
                                        end else if (stop_latched) begin
                                            state <= GEN_STOP;
                                        end else begin
                                            state <= IDLE;
                                        end
                                    end else begin
                                        if (stop_latched) begin
                                            state <= GEN_STOP;
                                        end else begin
                                            state <= IDLE;
                                        end
                                    end
                                end else if (timeout_count >= TIMEOUT_LIMIT) begin
                                    error_pulse <= 1'b1;
                                    state       <= ERROR;
                                    phase       <= 2'd0;
                                end
                            end
                        endcase
                    end

                    SEND_DATA: begin
                        case (phase)
                            2'd0: begin
                                scl_drive <= 1'b1;
                                sda_drive <= drive_for_bit(tx_shift[bit_idx]);
                                if (tick) begin
                                    scl_drive <= 1'b0;
                                    phase     <= 2'd1;
                                end
                            end
                            default: begin
                                scl_drive <= 1'b0;
                                if (scl_in && tx_shift[bit_idx] && !sda_in) begin
                                    arb_lost_pulse <= 1'b1;
                                    state          <= ARB_LOST;
                                    phase          <= 2'd0;
                                end else if (scl_in && tick) begin
                                    scl_drive <= 1'b1;
                                    phase     <= 2'd0;
                                    if (bit_cnt == 4'd0) begin
                                        sda_drive   <= 1'b0;
                                        ack_context <= ACK_DATA;
                                        state       <= WAIT_ACK;
                                    end else begin
                                        bit_cnt <= bit_cnt - 4'd1;
                                    end
                                end
                            end
                        endcase
                    end

                    READ_DATA: begin
                        sda_drive <= 1'b0;
                        case (phase)
                            2'd0: begin
                                scl_drive <= 1'b1;
                                if (tick) begin
                                    scl_drive     <= 1'b0;
                                    timeout_count <= 16'h0000;
                                    phase         <= 2'd1;
                                end
                            end
                            default: begin
                                scl_drive <= 1'b0;
                                if (scl_in) timeout_count <= 16'h0000;
                                else if (timeout_count < TIMEOUT_LIMIT) timeout_count <= timeout_count + 16'h0001;

                                if (scl_in && tick) begin
                                    scl_drive         <= 1'b1;
                                    phase             <= 2'd0;
                                    if (bit_cnt == 4'd0) begin
                                        rx_data        <= {rx_shift[7:1], sda_in};
                                        rx_valid_pulse <= 1'b1;
                                        state          <= SEND_ACK;
                                    end else begin
                                        rx_shift[bit_idx] <= sda_in;
                                        bit_cnt <= bit_cnt - 4'd1;
                                    end
                                end else if (timeout_count >= TIMEOUT_LIMIT) begin
                                    error_pulse <= 1'b1;
                                    state       <= ERROR;
                                    phase       <= 2'd0;
                                end
                            end
                        endcase
                    end

                    SEND_ACK: begin
                        master_ack_phase <= 1'b1;
                        case (phase)
                            2'd0: begin
                                scl_drive <= 1'b1;
                                sda_drive <= stop_latched ? 1'b0 : 1'b1;
                                if (tick) begin
                                    scl_drive <= 1'b0;
                                    phase     <= 2'd1;
                                end
                            end
                            default: begin
                                scl_drive <= 1'b0;
                                if (scl_in && tick) begin
                                    scl_drive <= 1'b1;
                                    sda_drive <= 1'b0;
                                    phase     <= 2'd0;
                                    if (stop_latched) begin
                                        state <= GEN_STOP;
                                    end else begin
                                        state <= IDLE;
                                    end
                                end
                            end
                        endcase
                    end

                    GEN_STOP: begin
                        case (phase)
                            2'd0: begin
                                scl_drive <= 1'b1;
                                sda_drive <= 1'b1;
                                if (tick) begin
                                    scl_drive     <= 1'b0;
                                    timeout_count <= 16'h0000;
                                    phase         <= 2'd1;
                                end
                            end
                            default: begin
                                scl_drive <= 1'b0;
                                sda_drive <= 1'b1;
                                if (scl_in) timeout_count <= 16'h0000;
                                else if (timeout_count < TIMEOUT_LIMIT) timeout_count <= timeout_count + 16'h0001;

                                if (scl_in && tick) begin
                                    sda_drive  <= 1'b0;
                                    bus_active <= 1'b0;
                                    state      <= IDLE;
                                    phase      <= 2'd0;
                                end else if (timeout_count >= TIMEOUT_LIMIT) begin
                                    sda_drive   <= 1'b0;
                                    scl_drive   <= 1'b0;
                                    bus_active  <= 1'b0;
                                    error_pulse <= 1'b1;
                                    state       <= ERROR;
                                    phase       <= 2'd0;
                                end
                            end
                        endcase
                    end

                    ARB_LOST: begin
                        sda_drive      <= 1'b0;
                        scl_drive      <= 1'b0;
                        bus_active     <= 1'b0;
                        arb_lost_pulse <= 1'b1;
                        state          <= IDLE;
                    end

                    ERROR: begin
                        error_pulse <= 1'b1;
                        if (stop_latched && bus_active) begin
                            state <= GEN_STOP;
                            phase <= 2'd0;
                        end else begin
                            sda_drive  <= 1'b0;
                            scl_drive  <= 1'b0;
                            bus_active <= 1'b0;
                            state      <= IDLE;
                        end
                    end

                    default: begin
                        state <= IDLE;
                    end
                endcase
            end
        end
    end

endmodule

// Repository status refresh: 2026-07-14
