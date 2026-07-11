`timescale 1ns/1ps
/*
 * Copyright (c) 2026 shivamtiwari020505
 * SPDX-License-Identifier: Apache-2.0
 */

module tb_wrapper_top;

    localparam CMD_START = 8'h01;
    localparam CMD_STOP  = 8'h02;
    localparam CMD_READ  = 8'h04;
    localparam CMD_WRITE = 8'h08;
    localparam CMD_REP   = 8'h10;

    localparam REG_SEL_DATA = 1'b0;
    localparam REG_SEL_CMD_STATUS = 1'b1;

    logic clk;
    logic rst_n;
    logic ena;
    logic [7:0] ui_in;
    logic [7:0] uio_drive;
    wire [7:0] uo_out;
    wire [7:0] uio_in;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;

    wire sda_bus;
    wire scl_bus;
    logic ext_sda_pull_low;
    logic ext_scl_pull_low;
    wire slave_bfm_saw_stretch;

    integer errors;
    integer i;
    reg [7:0] status_byte;
    reg [7:0] read_data;
    reg [7:0] obs_reg;
    reg [7:0] obs_data;
    reg [7:0] b0;
    reg [7:0] b1;
    reg [7:0] b2;
    reg [7:0] b3;
    bit ok;
    bit pointer_ok;
    bit wrapper_err_seen;

    pullup (sda_bus);
    pullup (scl_bus);

    assign sda_bus = (uio_oe[0] && !uio_out[0]) ? 1'b0 : 1'bz;
    assign scl_bus = (uio_oe[1] && !uio_out[1]) ? 1'b0 : 1'bz;
    assign sda_bus = ext_sda_pull_low ? 1'b0 : 1'bz;
    assign scl_bus = ext_scl_pull_low ? 1'b0 : 1'bz;
    assign uio_in[0] = sda_bus;
    assign uio_in[1] = scl_bus;
    assign uio_in[7:2] = uio_drive[7:2];


    i2c_master_bfm u_master_bfm (
        .SDA(sda_bus),
        .SCL(scl_bus)
    );

    i2c_slave_bfm u_slave_bfm (
        .SDA(sda_bus),
        .SCL(scl_bus),
        .saw_stretch(slave_bfm_saw_stretch)
    );

    tt_um_shivamtiwari020505_i2c dut (
        .ui_in(ui_in),
        .uo_out(uo_out),
        .uio_in(uio_in),
        .uio_out(uio_out),
        .uio_oe(uio_oe),
        .ena(ena),
        .clk(clk),
        .rst_n(rst_n)
    );

    initial begin
        clk = 1'b0;
        forever #10 clk = ~clk;
    end

    task fail;
        input [1023:0] msg;
        begin
            errors = errors + 1;
            $display("FAIL: %0s", msg);
        end
    endtask

    task expect_bit;
        input [1023:0] name;
        input bit got;
        begin
            if (!got) fail(name);
            else $display("PASS: %0s", name);
        end
    endtask

    task expect_eq8;
        input [1023:0] name;
        input [7:0] got;
        input [7:0] exp;
        begin
            if (got !== exp) begin
                $display("FAIL: %0s got 0x%02h expected 0x%02h", name, got, exp);
                errors = errors + 1;
            end else begin
                $display("PASS: %0s = 0x%02h", name, got);
            end
        end
    endtask

    task reset_tt;
        begin
            rst_n <= 1'b0;
            ena <= 1'b1;
            ui_in <= 8'h00;
            uio_drive <= 8'h00;
            ext_sda_pull_low <= 1'b0;
            ext_scl_pull_low <= 1'b0;
            u_master_bfm.release_bus();
            u_slave_bfm.release_bus();
            u_slave_bfm.reset_observed_flags();
            repeat (8) @(posedge clk);
            rst_n <= 1'b1;
            repeat (32) @(posedge clk);
        end
    endtask

    task pulse_wr;
        input bit reg_sel;
        input [7:0] data;
        begin
            @(posedge clk);
            ui_in <= data;
            uio_drive[4] <= reg_sel;
            uio_drive[2] <= 1'b1;
            @(posedge clk);
            uio_drive[2] <= 1'b0;
            repeat (4) @(posedge clk);
        end
    endtask

    task pulse_rd;
        input bit reg_sel;
        output [7:0] data;
        begin
            @(posedge clk);
            uio_drive[4] <= reg_sel;
            uio_drive[3] <= 1'b1;
            @(posedge clk);
            uio_drive[3] <= 1'b0;
            repeat (4) @(posedge clk);
            data = uo_out;
        end
    endtask

    task pulse_rd_capture_err;
        input bit reg_sel;
        output [7:0] data;
        output bit err_seen;
        integer sample;
        begin
            err_seen = 1'b0;
            @(posedge clk);
            uio_drive[4] <= reg_sel;
            uio_drive[3] <= 1'b1;
            err_seen = err_seen | uio_out[7];
            @(posedge clk);
            uio_drive[3] <= 1'b0;
            for (sample = 0; sample < 8; sample = sample + 1) begin
                @(posedge clk);
                err_seen = err_seen | uio_out[7];
            end
            data = uo_out;
        end
    endtask

    task pulse_irq_clear;
        begin
            @(posedge clk);
            uio_drive[6] <= 1'b1;
            @(posedge clk);
            uio_drive[6] <= 1'b0;
            repeat (6) @(posedge clk);
        end
    endtask

    task read_status;
        output [7:0] data;
        begin
            pulse_rd(REG_SEL_CMD_STATUS, data);
        end
    endtask

    task wait_master_idle;
        integer guard;
        begin
            guard = 0;
            while ((dut.u_core.u_master.state === 4'h0) && guard < 500000) begin
                guard = guard + 1;
                @(posedge clk);
            end
            if (guard >= 500000) fail("TT wrapper master did not accept command");

            guard = 0;
            while ((dut.u_core.u_master.state !== 4'h0) && guard < 500000) begin
                guard = guard + 1;
                @(posedge clk);
            end
            if (guard >= 500000) fail("TT wrapper master did not return to IDLE");
            repeat (20) @(posedge clk);
        end
    endtask

    task tt_master_write_byte;
        input [7:0] data;
        input bit start;
        input bit stop;
        input bit repeated;
        reg [7:0] cmd;
        begin
            cmd = CMD_WRITE;
            if (start) cmd = cmd | CMD_START;
            if (stop) cmd = cmd | CMD_STOP;
            if (repeated) cmd = cmd | CMD_REP;
            pulse_wr(REG_SEL_DATA, data);
            pulse_wr(REG_SEL_CMD_STATUS, cmd);
            wait_master_idle();
        end
    endtask

    task tt_master_read_byte;
        output [7:0] data;
        input bit start;
        input bit stop;
        input bit repeated;
        reg [7:0] cmd;
        begin
            cmd = CMD_READ;
            if (start) cmd = cmd | CMD_START;
            if (stop) cmd = cmd | CMD_STOP;
            if (repeated) cmd = cmd | CMD_REP;
            pulse_wr(REG_SEL_CMD_STATUS, cmd);
            wait_master_idle();
            pulse_rd(REG_SEL_DATA, data);
        end
    endtask

    task tt_master_read_to_fifo;
        input bit start;
        input bit stop;
        input bit repeated;
        reg [7:0] cmd;
        begin
            cmd = CMD_READ;
            if (start) cmd = cmd | CMD_START;
            if (stop) cmd = cmd | CMD_STOP;
            if (repeated) cmd = cmd | CMD_REP;
            pulse_wr(REG_SEL_CMD_STATUS, cmd);
            wait_master_idle();
        end
    endtask

    initial begin
        errors = 0;
        reset_tt();

        $display("TC18-TT DUT master writes external slave BFM through TT wrapper");
        fork
            u_slave_bfm.serve_write_one(7'h50, obs_reg, obs_data, 1'b0);
        join_none
        #1;
        tt_master_write_byte(8'h08, 1'b1, 1'b0, 1'b0);
        tt_master_write_byte(8'hA8, 1'b0, 1'b1, 1'b0);
        wait fork;
        expect_eq8("TC18-TT observed register", obs_reg, 8'h08);
        expect_eq8("TC18-TT observed data", obs_data, 8'hA8);

        $display("TC19-TT DUT master reads external slave BFM through TT wrapper");
        reset_tt();
        fork
            u_slave_bfm.serve_read_one(7'h50, 8'h09, 8'hB9, 1'b0, pointer_ok);
        join_none
        #1;
        tt_master_write_byte(8'h09, 1'b1, 1'b0, 1'b0);
        tt_master_read_byte(read_data, 1'b0, 1'b1, 1'b1);
        wait fork;
        expect_bit("TC19-TT pointer byte matched", pointer_ok);
        expect_eq8("TC19-TT read data", read_data, 8'hB9);

        $display("TC20-TT external master BFM writes DUT slave through TT wrapper");
        reset_tt();
        u_master_bfm.write_reg(7'h52, 8'h03, 8'hC3, ok);
        repeat (20) @(posedge clk);
        expect_bit("TC20-TT external master write ACKs", ok);
        expect_eq8("TC20-TT DUT slave reg[3]", dut.u_core.u_reg_file.mem[3], 8'hC3);

        $display("TC21-TT external master BFM reads DUT slave through TT wrapper");
        reset_tt();
        dut.u_core.u_reg_file.mem[4] = 8'hD4;
        u_master_bfm.read_reg(7'h52, 8'h04, read_data, ok);
        expect_bit("TC21-TT external master read ACKs", ok);
        expect_eq8("TC21-TT external master read data", read_data, 8'hD4);

        $display("TC22-TT external slave BFM NACKs DUT master address");
        reset_tt();
        fork
            u_slave_bfm.serve_nack_address();
        join_none
        #1;
        tt_master_write_byte(8'h00, 1'b1, 1'b1, 1'b0);
        wait fork;
        read_status(status_byte);
        expect_bit("TC22-TT DUT master ERROR after NACK", status_byte[7]);

        $display("TC23-TT external slave BFM stretches SCL");
        reset_tt();
        fork
            u_slave_bfm.serve_write_one(7'h50, obs_reg, obs_data, 1'b1);
        join_none
        #1;
        tt_master_write_byte(8'h0A, 1'b1, 1'b0, 1'b0);
        tt_master_write_byte(8'hCA, 1'b0, 1'b1, 1'b0);
        wait fork;
        expect_bit("TC23-TT external stretch observed", slave_bfm_saw_stretch);
        expect_eq8("TC23-TT observed register", obs_reg, 8'h0A);
        expect_eq8("TC23-TT observed data", obs_data, 8'hCA);

        $display("TC24-TT stuck-low SCL prevents DUT master START");
        reset_tt();
        ext_scl_pull_low <= 1'b1;
        repeat (20) @(posedge clk);
        pulse_wr(REG_SEL_DATA, 8'h55);
        pulse_wr(REG_SEL_CMD_STATUS, CMD_START | CMD_WRITE | CMD_STOP);
        repeat (1000) @(posedge clk);
        ext_scl_pull_low <= 1'b0;
        repeat (20) @(posedge clk);
        read_status(status_byte);
        expect_bit("TC24-TT DUT master ERROR on stuck SCL", status_byte[7]);

        $display("TC25-TT external master BFM burst writes DUT slave");
        reset_tt();
        u_master_bfm.write_burst4(7'h52, 8'h00, 8'hE0, 8'hE1, 8'hE2, 8'hE3, ok);
        repeat (20) @(posedge clk);
        expect_bit("TC25-TT burst write ACKs", ok);
        expect_eq8("TC25-TT DUT slave reg[0]", dut.u_core.u_reg_file.mem[0], 8'hE0);
        expect_eq8("TC25-TT DUT slave reg[1]", dut.u_core.u_reg_file.mem[1], 8'hE1);
        expect_eq8("TC25-TT DUT slave reg[2]", dut.u_core.u_reg_file.mem[2], 8'hE2);
        expect_eq8("TC25-TT DUT slave reg[3]", dut.u_core.u_reg_file.mem[3], 8'hE3);

        $display("TC26-TT external master BFM burst reads DUT slave");
        reset_tt();
        dut.u_core.u_reg_file.mem[0] = 8'hF0;
        dut.u_core.u_reg_file.mem[1] = 8'hF1;
        dut.u_core.u_reg_file.mem[2] = 8'hF2;
        dut.u_core.u_reg_file.mem[3] = 8'hF3;
        u_master_bfm.read_burst4(7'h52, 8'h00, b0, b1, b2, b3, ok);
        expect_bit("TC26-TT burst read ACKs", ok);
        expect_eq8("TC26-TT burst read byte0", b0, 8'hF0);
        expect_eq8("TC26-TT burst read byte1", b1, 8'hF1);
        expect_eq8("TC26-TT burst read byte2", b2, 8'hF2);
        expect_eq8("TC26-TT burst read byte3", b3, 8'hF3);

        $display("TC27-TT external slave BFM NACKs data byte");
        reset_tt();
        fork
            u_slave_bfm.serve_write_data_nack(7'h50, obs_reg, obs_data);
        join_none
        #1;
        tt_master_write_byte(8'h0B, 1'b1, 1'b0, 1'b0);
        tt_master_write_byte(8'hDB, 1'b0, 1'b1, 1'b0);
        wait fork;
        read_status(status_byte);
        expect_eq8("TC27-TT observed register", obs_reg, 8'h0B);
        expect_eq8("TC27-TT observed data", obs_data, 8'hDB);
        expect_bit("TC27-TT DUT master ERROR after data NACK", status_byte[7]);

        $display("TC28-TT external master BFM STOP after pointer only");
        reset_tt();
        dut.u_core.u_reg_file.mem[5] = 8'h5E;
        u_master_bfm.write_pointer_only(7'h52, 8'h05, ok);
        repeat (20) @(posedge clk);
        expect_bit("TC28-TT pointer-only write ACKs", ok);
        expect_eq8("TC28-TT pointer-only did not overwrite reg[5]", dut.u_core.u_reg_file.mem[5], 8'h5E);

        $display("TC29-TT wrapper pin direction sanity");
        reset_tt();
        if (uio_oe[6] !== 1'b0 || uio_oe[4:2] !== 3'b000) fail("TC29-TT control and IRQ_CLEAR uio outputs not input-only");
        else $display("PASS: TC29-TT control and IRQ_CLEAR uio outputs input-only");
        expect_bit("TC29-TT IRQ pin is output-enabled", uio_oe[5]);
        expect_bit("TC29-TT WRAPPER_ERR pin is output-enabled", uio_oe[7]);

        $display("TC30-TT WRAPPER_ERR pulse and IRQ_CLEAR pin");
        reset_tt();
        pulse_rd_capture_err(REG_SEL_DATA, read_data, wrapper_err_seen);
        expect_bit("TC30-TT WRAPPER_ERR pulses on RX underflow", wrapper_err_seen);
        repeat (2) @(posedge clk);
        expect_bit("TC30-TT IRQ set after RX underflow", uio_out[5]);
        pulse_irq_clear();
        if (uio_out[5] !== 1'b0) fail("TC30-TT IRQ did not clear from uio[6] pulse");
        else $display("PASS: TC30-TT IRQ clears from uio[6] pulse");

        if (errors == 0) begin
            $display("ALL TINY TAPEOUT WRAPPER BUS REGRESSION TESTS PASSED");
            $finish;
        end else begin
            $display("TINY TAPEOUT WRAPPER BUS REGRESSION TESTS FAILED: %0d error(s)", errors);
            $fatal(1);
        end
    end

endmodule
