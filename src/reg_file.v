`timescale 1ns/1ps
/*
 * Copyright (c) 2026 shivamtiwari020505
 * SPDX-License-Identifier: Apache-2.0
 */

module reg_file #(
    parameter DATA_WIDTH = 8,
    parameter NUM_REGS   = 16,
    parameter ADDR_WIDTH = 4
) (
    input  wire                  clk,
    input  wire                  resetn,
    input  wire                  wr_en,
    input  wire [ADDR_WIDTH-1:0] wr_addr,
    input  wire [DATA_WIDTH-1:0] wr_data,
    input  wire [ADDR_WIDTH-1:0] rd_addr,
    output wire [DATA_WIDTH-1:0] rd_data
);

    reg [DATA_WIDTH-1:0] mem [0:NUM_REGS-1];
    integer i;

    always @(posedge clk) begin
        if (!resetn) begin
            for (i = 0; i < NUM_REGS; i = i + 1) begin
                mem[i] <= {DATA_WIDTH{1'b0}};
            end
        end else if (wr_en) begin
            mem[wr_addr] <= wr_data;
        end
    end

    assign rd_data = mem[rd_addr];

endmodule

// Repository status refresh: 2026-07-14
