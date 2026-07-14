`timescale 1ns/1ps
/*
 * Copyright (c) 2026 shivamtiwari020505
 * SPDX-License-Identifier: Apache-2.0
 */

module sync_fifo #(
    parameter DATA_WIDTH = 8,
    parameter DEPTH      = 8,
    parameter ADDR_WIDTH = 3
) (
    input  wire                  clk,
    input  wire                  resetn,
    input  wire                  clear,
    input  wire                  wr_en,
    input  wire [DATA_WIDTH-1:0] wr_data,
    input  wire                  rd_en,
    output wire [DATA_WIDTH-1:0] rd_data,
    output wire                  empty,
    output wire                  full,
    output reg  [ADDR_WIDTH:0]   count
);

    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    reg [ADDR_WIDTH-1:0] wr_ptr;
    reg [ADDR_WIDTH-1:0] rd_ptr;
    localparam [ADDR_WIDTH:0] DEPTH_COUNT = DEPTH;
    localparam [ADDR_WIDTH:0] DEPTH_MINUS_ONE_COUNT = DEPTH_COUNT - {{ADDR_WIDTH{1'b0}}, 1'b1};
    localparam [ADDR_WIDTH-1:0] LAST_PTR = DEPTH_MINUS_ONE_COUNT[ADDR_WIDTH-1:0];

    wire do_write = wr_en & ~full;
    wire do_read  = rd_en & ~empty;

    assign empty = (count == {((ADDR_WIDTH+1)){1'b0}});
    assign full  = (count == DEPTH_COUNT);
    assign rd_data = empty ? {DATA_WIDTH{1'b0}} : mem[rd_ptr];

    function [ADDR_WIDTH-1:0] ptr_next;
        input [ADDR_WIDTH-1:0] ptr;
        begin
            if (ptr == LAST_PTR)
                ptr_next = {ADDR_WIDTH{1'b0}};
            else
                ptr_next = ptr + {{(ADDR_WIDTH-1){1'b0}}, 1'b1};
        end
    endfunction

    always @(posedge clk) begin
        if (!resetn || clear) begin
            wr_ptr <= {ADDR_WIDTH{1'b0}};
            rd_ptr <= {ADDR_WIDTH{1'b0}};
            count  <= {((ADDR_WIDTH+1)){1'b0}};
        end else begin
            if (do_write) begin
                mem[wr_ptr] <= wr_data;
                wr_ptr <= ptr_next(wr_ptr);
            end

            if (do_read) begin
                rd_ptr <= ptr_next(rd_ptr);
            end

            case ({do_write, do_read})
                2'b10: count <= count + {{ADDR_WIDTH{1'b0}}, 1'b1};
                2'b01: count <= count - {{ADDR_WIDTH{1'b0}}, 1'b1};
                default: count <= count;
            endcase
        end
    end

endmodule

// Repository status refresh: 2026-07-14
