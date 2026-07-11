`timescale 1ns/1ps
/*
 * Copyright (c) 2026 shivamtiwari020505
 * SPDX-License-Identifier: Apache-2.0
 */

module i2c_master_bfm #(
    parameter integer HALF_PERIOD_NS = 2500,
    parameter integer TIMEOUT_CYCLES = 10000
) (
    inout tri1 SDA,
    inout tri1 SCL
);

    logic sda_pull_low;
    logic scl_pull_low;

    assign SDA = sda_pull_low ? 1'b0 : 1'bz;
    assign SCL = scl_pull_low ? 1'b0 : 1'bz;

    initial begin
        sda_pull_low = 1'b0;
        scl_pull_low = 1'b0;
    end

    task release_bus;
        begin
            sda_pull_low = 1'b0;
            scl_pull_low = 1'b0;
        end
    endtask

    task wait_scl_high;
        integer guard;
        begin
            guard = 0;
            scl_pull_low = 1'b0;
            while ((SCL !== 1'b1) && (guard < TIMEOUT_CYCLES)) begin
                guard = guard + 1;
                #(HALF_PERIOD_NS / 10);
            end
            if (guard >= TIMEOUT_CYCLES) begin
                $error("i2c_master_bfm timed out waiting for SCL high");
            end
        end
    endtask

    task start_cond;
        begin
            sda_pull_low = 1'b0;
            scl_pull_low = 1'b0;
            wait_scl_high();
            #(HALF_PERIOD_NS);
            sda_pull_low = 1'b1;
            #(HALF_PERIOD_NS);
            scl_pull_low = 1'b1;
            #(HALF_PERIOD_NS);
        end
    endtask

    task repeated_start_cond;
        begin
            sda_pull_low = 1'b0;
            #(HALF_PERIOD_NS);
            scl_pull_low = 1'b0;
            wait_scl_high();
            #(HALF_PERIOD_NS);
            sda_pull_low = 1'b1;
            #(HALF_PERIOD_NS);
            scl_pull_low = 1'b1;
            #(HALF_PERIOD_NS);
        end
    endtask

    task stop_cond;
        begin
            sda_pull_low = 1'b1;
            #(HALF_PERIOD_NS);
            scl_pull_low = 1'b0;
            wait_scl_high();
            #(HALF_PERIOD_NS);
            sda_pull_low = 1'b0;
            #(HALF_PERIOD_NS);
        end
    endtask

    task write_bit;
        input bit value;
        begin
            sda_pull_low = ~value;
            #(HALF_PERIOD_NS);
            scl_pull_low = 1'b0;
            wait_scl_high();
            #(HALF_PERIOD_NS);
            scl_pull_low = 1'b1;
            #(HALF_PERIOD_NS);
        end
    endtask

    task read_bit;
        output bit value;
        begin
            sda_pull_low = 1'b0;
            #(HALF_PERIOD_NS);
            scl_pull_low = 1'b0;
            wait_scl_high();
            #(HALF_PERIOD_NS / 2);
            value = SDA;
            #(HALF_PERIOD_NS / 2);
            scl_pull_low = 1'b1;
            #(HALF_PERIOD_NS);
        end
    endtask

    task write_byte;
        input [7:0] data;
        output bit ack;
        bit ack_bit;
        integer i;
        begin
            for (i = 7; i >= 0; i = i - 1) begin
                write_bit(data[i]);
            end
            read_bit(ack_bit);
            ack = ~ack_bit;
        end
    endtask

    task read_byte;
        output [7:0] data;
        input bit ack;
        bit bit_value;
        integer i;
        begin
            for (i = 7; i >= 0; i = i - 1) begin
                read_bit(bit_value);
                data[i] = bit_value;
            end
            write_bit(~ack);
            sda_pull_low = 1'b0;
        end
    endtask

    task write_reg;
        input [6:0] addr;
        input [7:0] reg_addr;
        input [7:0] data;
        output bit ok;
        bit ack;
        begin
            ok = 1'b1;
            start_cond();
            write_byte({addr, 1'b0}, ack);
            ok = ok & ack;
            write_byte(reg_addr, ack);
            ok = ok & ack;
            write_byte(data, ack);
            ok = ok & ack;
            stop_cond();
        end
    endtask

    task read_reg;
        input [6:0] addr;
        input [7:0] reg_addr;
        output [7:0] data;
        output bit ok;
        bit ack;
        begin
            ok = 1'b1;
            start_cond();
            write_byte({addr, 1'b0}, ack);
            ok = ok & ack;
            write_byte(reg_addr, ack);
            ok = ok & ack;
            repeated_start_cond();
            write_byte({addr, 1'b1}, ack);
            ok = ok & ack;
            read_byte(data, 1'b0);
            stop_cond();
        end
    endtask

    task write_pointer_only;
        input [6:0] addr;
        input [7:0] reg_addr;
        output bit ok;
        bit ack;
        begin
            ok = 1'b1;
            start_cond();
            write_byte({addr, 1'b0}, ack);
            ok = ok & ack;
            write_byte(reg_addr, ack);
            ok = ok & ack;
            stop_cond();
        end
    endtask

    task write_burst4;
        input [6:0] addr;
        input [7:0] reg_addr;
        input [7:0] data0;
        input [7:0] data1;
        input [7:0] data2;
        input [7:0] data3;
        output bit ok;
        bit ack;
        begin
            ok = 1'b1;
            start_cond();
            write_byte({addr, 1'b0}, ack);
            ok = ok & ack;
            write_byte(reg_addr, ack);
            ok = ok & ack;
            write_byte(data0, ack);
            ok = ok & ack;
            write_byte(data1, ack);
            ok = ok & ack;
            write_byte(data2, ack);
            ok = ok & ack;
            write_byte(data3, ack);
            ok = ok & ack;
            stop_cond();
        end
    endtask

    task read_burst4;
        input [6:0] addr;
        input [7:0] reg_addr;
        output [7:0] data0;
        output [7:0] data1;
        output [7:0] data2;
        output [7:0] data3;
        output bit ok;
        bit ack;
        begin
            ok = 1'b1;
            start_cond();
            write_byte({addr, 1'b0}, ack);
            ok = ok & ack;
            write_byte(reg_addr, ack);
            ok = ok & ack;
            repeated_start_cond();
            write_byte({addr, 1'b1}, ack);
            ok = ok & ack;
            read_byte(data0, 1'b1);
            read_byte(data1, 1'b1);
            read_byte(data2, 1'b1);
            read_byte(data3, 1'b0);
            stop_cond();
        end
    endtask

endmodule
