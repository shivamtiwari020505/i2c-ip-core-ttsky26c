`timescale 1ns/1ps
/*
 * Copyright (c) 2026 shivamtiwari020505
 * SPDX-License-Identifier: Apache-2.0
 */

module i2c_slave_fsm #(
    parameter NUM_REGS       = 16,
    parameter REG_ADDR_WIDTH = 4,
    parameter STRETCH_CYCLES = 16
) (
    input  wire                  clk,
    input  wire                  resetn,
    input  wire                  enable,
    input  wire [6:0]            slave_addr,
    input  wire                  sda_in,
    input  wire                  scl_in,
    output reg                   sda_drive,
    output reg                   scl_drive,
    output reg                   reg_wr_en,
    output reg  [REG_ADDR_WIDTH-1:0] reg_wr_addr,
    output reg  [7:0]            reg_wr_data,
    output wire [REG_ADDR_WIDTH-1:0] reg_rd_addr,
    input  wire [7:0]            reg_rd_data,
    output reg                   stretch_active,
    output reg                   address_match_pulse,
    output reg                   rx_done_pulse,
    output reg                   tx_done_pulse,
    output reg  [2:0]            state
);

    localparam IDLE      = 3'h0;
    localparam RCV_ADDR  = 3'h1;
    localparam CHK_ADDR  = 3'h2;
    localparam SEND_ACK  = 3'h3;
    localparam RCV_DATA  = 3'h4;
    localparam SEND_DATA = 3'h5;
    localparam DATA_ACK  = 3'h6;
    localparam DONE      = 3'h7;
    localparam [15:0] STRETCH_LIMIT = STRETCH_CYCLES;

    reg sda_d;
    reg scl_d;
    reg [7:1] shift;
    reg [7:0] data_byte;
    reg [7:0] tx_shift;
    reg [3:0] bit_cnt;
    reg [REG_ADDR_WIDTH-1:0] pointer;
    reg rw_bit;
    reg matched;
    reg expect_pointer;
    reg ack_started;
    reg ack_drive_active;
    reg read_ack_phase;
    reg send_loaded;
    reg master_ack;
    reg [15:0] stretch_count;
    wire [2:0] bit_idx = bit_cnt[2:0];

    wire scl_rise  = (~scl_d) & scl_in;
    wire scl_fall  = scl_d & (~scl_in);
    wire start_det = sda_d & (~sda_in) & scl_in;
    wire stop_det  = (~sda_d) & sda_in & scl_in;

    assign reg_rd_addr = pointer;

    localparam [REG_ADDR_WIDTH:0] NUM_REGS_COUNT = NUM_REGS;
    localparam [REG_ADDR_WIDTH:0] LAST_REG_COUNT = NUM_REGS_COUNT - {{REG_ADDR_WIDTH{1'b0}}, 1'b1};
    localparam [REG_ADDR_WIDTH-1:0] LAST_REG_ADDR = LAST_REG_COUNT[REG_ADDR_WIDTH-1:0];

    function [REG_ADDR_WIDTH-1:0] pointer_next;
        input [REG_ADDR_WIDTH-1:0] value;
        begin
            if (value == LAST_REG_ADDR)
                pointer_next = {REG_ADDR_WIDTH{1'b0}};
            else
                pointer_next = value + {{(REG_ADDR_WIDTH-1){1'b0}}, 1'b1};
        end
    endfunction

    always @(posedge clk) begin
        if (!resetn) begin
            state               <= IDLE;
            sda_drive           <= 1'b0;
            scl_drive           <= 1'b0;
            reg_wr_en           <= 1'b0;
            reg_wr_addr         <= {REG_ADDR_WIDTH{1'b0}};
            reg_wr_data         <= 8'h00;
            stretch_active      <= 1'b0;
            address_match_pulse <= 1'b0;
            rx_done_pulse       <= 1'b0;
            tx_done_pulse       <= 1'b0;
            sda_d               <= 1'b1;
            scl_d               <= 1'b1;
            shift               <= 7'h00;
            data_byte           <= 8'h00;
            tx_shift            <= 8'h00;
            bit_cnt             <= 4'd0;
            pointer             <= {REG_ADDR_WIDTH{1'b0}};
            rw_bit              <= 1'b0;
            matched             <= 1'b0;
            expect_pointer      <= 1'b1;
            ack_started         <= 1'b0;
            ack_drive_active    <= 1'b0;
            read_ack_phase      <= 1'b0;
            send_loaded         <= 1'b0;
            master_ack          <= 1'b0;
            stretch_count       <= 16'h0000;
        end else begin
            sda_d <= sda_in;
            scl_d <= scl_in;

            reg_wr_en           <= 1'b0;
            address_match_pulse <= 1'b0;
            rx_done_pulse       <= 1'b0;
            tx_done_pulse       <= 1'b0;

            if (!enable) begin
                state            <= IDLE;
                sda_drive        <= 1'b0;
                scl_drive        <= 1'b0;
                stretch_active   <= 1'b0;
                ack_started      <= 1'b0;
                ack_drive_active <= 1'b0;
            end else if (start_det) begin
                state            <= RCV_ADDR;
                bit_cnt          <= 4'd7;
                shift            <= 7'h00;
                sda_drive        <= 1'b0;
                scl_drive        <= 1'b0;
                stretch_active   <= 1'b0;
                ack_started      <= 1'b0;
                ack_drive_active <= 1'b0;
                send_loaded      <= 1'b0;
            end else if (stop_det && (state != IDLE)) begin
                state            <= DONE;
                sda_drive        <= 1'b0;
                scl_drive        <= 1'b0;
                stretch_active   <= 1'b0;
                ack_started      <= 1'b0;
                ack_drive_active <= 1'b0;
            end else begin
                case (state)
                    IDLE: begin
                        sda_drive        <= 1'b0;
                        scl_drive        <= 1'b0;
                        stretch_active   <= 1'b0;
                        ack_started      <= 1'b0;
                        ack_drive_active <= 1'b0;
                    end

                    RCV_ADDR: begin
                        sda_drive <= 1'b0;
                        if (scl_rise) begin
                            if (bit_cnt == 4'd0) begin
                                data_byte <= {shift[7:1], sda_in};
                                state     <= CHK_ADDR;
                            end else begin
                                shift[bit_idx] <= sda_in;
                                bit_cnt <= bit_cnt - 4'd1;
                            end
                        end
                    end

                    CHK_ADDR: begin
                        matched             <= (data_byte[7:1] == slave_addr);
                        rw_bit              <= data_byte[0];
                        expect_pointer      <= ~data_byte[0];
                        address_match_pulse <= (data_byte[7:1] == slave_addr);
                        ack_started         <= 1'b0;
                        ack_drive_active    <= 1'b0;
                        stretch_count       <= 16'h0000;
                        state               <= SEND_ACK;
                    end

                    SEND_ACK: begin
                        if (scl_fall && !ack_started) begin
                            ack_drive_active <= 1'b1;
                            stretch_active   <= (STRETCH_CYCLES != 0);
                            stretch_count    <= 16'h0000;
                        end

                        if (stretch_active) begin
                            scl_drive <= 1'b1;
                            if (stretch_count >= STRETCH_LIMIT) begin
                                stretch_active <= 1'b0;
                                scl_drive      <= 1'b0;
                            end else begin
                                stretch_count <= stretch_count + 16'h0001;
                            end
                        end else begin
                            scl_drive <= 1'b0;
                        end

                        sda_drive <= matched & ack_drive_active;

                        if (scl_rise) begin
                            ack_started <= 1'b1;
                        end

                        if (scl_fall && ack_started) begin
                            sda_drive        <= 1'b0;
                            ack_drive_active <= 1'b0;
                            ack_started      <= 1'b0;
                            if (!matched) begin
                                state <= DONE;
                            end else if (rw_bit) begin
                                send_loaded <= 1'b0;
                                state       <= SEND_DATA;
                            end else begin
                                bit_cnt <= 4'd7;
                                shift   <= 7'h00;
                                state   <= RCV_DATA;
                            end
                        end
                    end

                    RCV_DATA: begin
                        sda_drive <= 1'b0;
                        if (scl_rise) begin
                            if (bit_cnt == 4'd0) begin
                                data_byte <= {shift[7:1], sda_in};
                                if (expect_pointer) begin
                                    pointer        <= {shift[REG_ADDR_WIDTH-1:1], sda_in};
                                    expect_pointer <= 1'b0;
                                end else begin
                                    reg_wr_en   <= 1'b1;
                                    reg_wr_addr <= pointer;
                                    reg_wr_data <= {shift[7:1], sda_in};
                                    pointer     <= pointer_next(pointer);
                                end
                                rx_done_pulse    <= 1'b1;
                                ack_started      <= 1'b0;
                                ack_drive_active <= 1'b0;
                                read_ack_phase   <= 1'b0;
                                state            <= DATA_ACK;
                            end else begin
                                shift[bit_idx] <= sda_in;
                                bit_cnt <= bit_cnt - 4'd1;
                            end
                        end
                    end

                    SEND_DATA: begin
                        if (!send_loaded) begin
                            tx_shift    <= reg_rd_data;
                            bit_cnt     <= 4'd7;
                            send_loaded <= 1'b1;
                        end else begin
                            if (!scl_in || scl_fall) begin
                                sda_drive <= ~tx_shift[bit_idx];
                            end
                            if (scl_fall) begin
                                if (bit_cnt == 4'd0) begin
                                    sda_drive      <= 1'b0;
                                    ack_started    <= 1'b0;
                                    read_ack_phase <= 1'b1;
                                    state          <= DATA_ACK;
                                end else begin
                                    bit_cnt <= bit_cnt - 4'd1;
                                end
                            end
                        end
                    end

                    DATA_ACK: begin
                        if (read_ack_phase) begin
                            sda_drive <= 1'b0;
                            if (scl_rise) begin
                                master_ack  <= ~sda_in;
                                ack_started <= 1'b1;
                            end
                            if (scl_fall && ack_started) begin
                                tx_done_pulse  <= 1'b1;
                                ack_started    <= 1'b0;
                                read_ack_phase <= 1'b0;
                                if (master_ack) begin
                                    pointer     <= pointer_next(pointer);
                                    send_loaded <= 1'b0;
                                    state       <= SEND_DATA;
                                end else begin
                                    pointer <= pointer_next(pointer);
                                    state   <= DONE;
                                end
                            end
                        end else begin
                            if (scl_fall && !ack_started) begin
                                ack_drive_active <= 1'b1;
                                stretch_active   <= (STRETCH_CYCLES != 0);
                                stretch_count    <= 16'h0000;
                            end

                            if (stretch_active) begin
                                scl_drive <= 1'b1;
                                if (stretch_count >= STRETCH_LIMIT) begin
                                    stretch_active <= 1'b0;
                                    scl_drive      <= 1'b0;
                                end else begin
                                    stretch_count <= stretch_count + 16'h0001;
                                end
                            end else begin
                                scl_drive <= 1'b0;
                            end

                            sda_drive <= ack_drive_active;

                            if (scl_rise) begin
                                ack_started <= 1'b1;
                            end
                            if (scl_fall && ack_started) begin
                                sda_drive        <= 1'b0;
                                ack_drive_active <= 1'b0;
                                ack_started      <= 1'b0;
                                bit_cnt          <= 4'd7;
                                shift            <= 7'h00;
                                state            <= RCV_DATA;
                            end
                        end
                    end

                    DONE: begin
                        sda_drive        <= 1'b0;
                        scl_drive        <= 1'b0;
                        stretch_active   <= 1'b0;
                        ack_started      <= 1'b0;
                        ack_drive_active <= 1'b0;
                        state            <= IDLE;
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
