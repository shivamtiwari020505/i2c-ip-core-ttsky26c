`timescale 1ns/1ps
/*
 * Copyright (c) 2026 shivamtiwari020505
 * SPDX-License-Identifier: Apache-2.0
 */

module clk_divider #(
    parameter PRESCALER_WIDTH = 16
) (
    input  wire                       clk,
    input  wire                       resetn,
    input  wire                       enable,
    input  wire [PRESCALER_WIDTH-1:0] prescaler,
    output reg                        tick
);

    reg [PRESCALER_WIDTH-1:0] count;

    always @(posedge clk) begin
        if (!resetn) begin
            count <= {PRESCALER_WIDTH{1'b0}};
            tick  <= 1'b0;
        end else if (!enable) begin
            count <= {PRESCALER_WIDTH{1'b0}};
            tick  <= 1'b0;
        end else if (count >= prescaler) begin
            count <= {PRESCALER_WIDTH{1'b0}};
            tick  <= 1'b1;
        end else begin
            count <= count + {{(PRESCALER_WIDTH-1){1'b0}}, 1'b1};
            tick  <= 1'b0;
        end
    end

endmodule

// Repository status refresh: 2026-07-14
