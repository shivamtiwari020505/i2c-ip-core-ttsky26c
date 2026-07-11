`timescale 1ns/1ps
/*
 * Copyright (c) 2026 shivamtiwari020505
 * SPDX-License-Identifier: Apache-2.0
 */

module i2c_slave_bfm #(
    parameter integer STRETCH_NS = 5000,
    parameter integer TIMEOUT_CYCLES = 100000
) (
    inout tri1 SDA,
    inout tri1 SCL,
    output logic saw_stretch
);

    logic sda_pull_low;
    logic scl_pull_low;

    assign SDA = sda_pull_low ? 1'b0 : 1'bz;
    assign SCL = scl_pull_low ? 1'b0 : 1'bz;

    initial begin
        sda_pull_low = 1'b0;
        scl_pull_low = 1'b0;
        saw_stretch = 1'b0;
    end

    task reset_observed_flags;
        begin
            saw_stretch = 1'b0;
        end
    endtask

    task release_bus;
        begin
            sda_pull_low = 1'b0;
            scl_pull_low = 1'b0;
        end
    endtask

    task wait_start;
        integer guard;
        begin
            guard = 0;
            while (!((SDA === 1'b0) && (SCL === 1'b1)) && (guard < TIMEOUT_CYCLES)) begin
                @(negedge SDA or posedge SCL);
                guard = guard + 1;
            end
            if (guard >= TIMEOUT_CYCLES) begin
                $error("i2c_slave_bfm timed out waiting for START");
            end
            @(negedge SCL);
        end
    endtask

    task wait_stop_or_bus_release;
        integer guard;
        begin
            guard = 0;
            while (!((SDA === 1'b1) && (SCL === 1'b1)) && (guard < TIMEOUT_CYCLES)) begin
                @(posedge SDA or posedge SCL);
                guard = guard + 1;
            end
            if (guard >= TIMEOUT_CYCLES) begin
                $error("i2c_slave_bfm timed out waiting for STOP/bus release");
            end
        end
    endtask

    task receive_bit;
        output bit value;
        begin
            @(posedge SCL);
            #1;
            value = SDA;
            @(negedge SCL);
        end
    endtask

    task receive_byte;
        output [7:0] data;
        bit bit_value;
        integer i;
        begin
            data = 8'h00;
            for (i = 7; i >= 0; i = i - 1) begin
                receive_bit(bit_value);
                data[i] = bit_value;
            end
        end
    endtask

    task send_ack;
        input bit ack;
        input bit stretch;
        begin
            if (stretch) begin
                saw_stretch = 1'b1;
                scl_pull_low = 1'b1;
                #(STRETCH_NS);
                scl_pull_low = 1'b0;
            end

            sda_pull_low = ack;
            @(posedge SCL);
            @(negedge SCL);
            sda_pull_low = 1'b0;
        end
    endtask

    task transmit_byte;
        input [7:0] data;
        output bit master_ack;
        integer i;
        begin
            for (i = 7; i >= 0; i = i - 1) begin
                sda_pull_low = ~data[i];
                @(posedge SCL);
                @(negedge SCL);
            end

            sda_pull_low = 1'b0;
            @(posedge SCL);
            #1;
            master_ack = ~SDA;
            @(negedge SCL);
        end
    endtask

    task serve_write_one;
        input [6:0] addr;
        output [7:0] observed_reg;
        output [7:0] observed_data;
        input bit stretch_ack;
        reg [7:0] byte_value;
        begin
            observed_reg = 8'h00;
            observed_data = 8'h00;
            release_bus();
            wait_start();

            receive_byte(byte_value);
            send_ack((byte_value[7:1] == addr) && (byte_value[0] == 1'b0), stretch_ack);

            receive_byte(observed_reg);
            send_ack(1'b1, stretch_ack);

            receive_byte(observed_data);
            send_ack(1'b1, stretch_ack);

            wait_stop_or_bus_release();
            release_bus();
        end
    endtask

    task serve_read_one;
        input [6:0] addr;
        input [7:0] expected_reg;
        input [7:0] data;
        input bit stretch_ack;
        output bit pointer_ok;
        reg [7:0] byte_value;
        bit master_ack;
        begin
            pointer_ok = 1'b0;
            release_bus();
            wait_start();

            receive_byte(byte_value);
            send_ack((byte_value[7:1] == addr) && (byte_value[0] == 1'b0), stretch_ack);

            receive_byte(byte_value);
            pointer_ok = (byte_value == expected_reg);
            send_ack(1'b1, stretch_ack);

            wait_start();
            receive_byte(byte_value);
            send_ack((byte_value[7:1] == addr) && (byte_value[0] == 1'b1), stretch_ack);

            transmit_byte(data, master_ack);
            wait_stop_or_bus_release();
            release_bus();
        end
    endtask

    task serve_nack_address;
        reg [7:0] byte_value;
        begin
            release_bus();
            wait_start();
            receive_byte(byte_value);
            send_ack(1'b0, 1'b0);
            wait_stop_or_bus_release();
            release_bus();
        end
    endtask

    task serve_write_data_nack;
        input [6:0] addr;
        output [7:0] observed_reg;
        output [7:0] observed_data;
        reg [7:0] byte_value;
        begin
            observed_reg = 8'h00;
            observed_data = 8'h00;
            release_bus();
            wait_start();

            receive_byte(byte_value);
            send_ack((byte_value[7:1] == addr) && (byte_value[0] == 1'b0), 1'b0);

            receive_byte(observed_reg);
            send_ack(1'b1, 1'b0);

            receive_byte(observed_data);
            send_ack(1'b0, 1'b0);

            wait_stop_or_bus_release();
            release_bus();
        end
    endtask

endmodule
