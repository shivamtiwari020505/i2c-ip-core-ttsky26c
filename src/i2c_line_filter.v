`timescale 1ns/1ps
/*
 * Copyright (c) 2026 shivamtiwari020505
 * SPDX-License-Identifier: Apache-2.0
 */

module i2c_line_filter #(
    parameter SYNC_STAGES = 2,
    parameter FILTER_LEN  = 1
) (
    input  wire clk,
    input  wire resetn,
    input  wire raw_sda,
    input  wire raw_scl,
    output wire sda_out,
    output wire scl_out
);

    reg [SYNC_STAGES-1:0] sda_sync;
    reg [SYNC_STAGES-1:0] scl_sync;
    reg sda_filtered;
    reg scl_filtered;

    assign sda_out = sda_filtered;
    assign scl_out = scl_filtered;

    generate
        if (SYNC_STAGES <= 1) begin : g_single_stage_sync
            always @(posedge clk) begin
                if (!resetn) begin
                    sda_sync <= {SYNC_STAGES{1'b1}};
                    scl_sync <= {SYNC_STAGES{1'b1}};
                end else begin
                    sda_sync[0] <= raw_sda;
                    scl_sync[0] <= raw_scl;
                end
            end
        end else begin : g_multi_stage_sync
            always @(posedge clk) begin
                if (!resetn) begin
                    sda_sync <= {SYNC_STAGES{1'b1}};
                    scl_sync <= {SYNC_STAGES{1'b1}};
                end else begin
                    sda_sync <= {sda_sync[SYNC_STAGES-2:0], raw_sda};
                    scl_sync <= {scl_sync[SYNC_STAGES-2:0], raw_scl};
                end
            end
        end
    endgenerate

    generate
        if (FILTER_LEN <= 1) begin : g_no_filter
            always @(posedge clk) begin
                if (!resetn) begin
                    sda_filtered <= 1'b1;
                    scl_filtered <= 1'b1;
                end else begin
                    sda_filtered <= sda_sync[SYNC_STAGES-1];
                    scl_filtered <= scl_sync[SYNC_STAGES-1];
                end
            end
        end else begin : g_stability_filter
            localparam [15:0] FILTER_LIMIT = FILTER_LEN - 1;
            reg [15:0] sda_count;
            reg [15:0] scl_count;

            always @(posedge clk) begin
                if (!resetn) begin
                    sda_filtered <= 1'b1;
                    scl_filtered <= 1'b1;
                    sda_count    <= 16'h0000;
                    scl_count    <= 16'h0000;
                end else begin
                    if (sda_sync[SYNC_STAGES-1] == sda_filtered) begin
                        sda_count <= 16'h0000;
                    end else if (sda_count >= FILTER_LIMIT) begin
                        sda_filtered <= sda_sync[SYNC_STAGES-1];
                        sda_count    <= 16'h0000;
                    end else begin
                        sda_count <= sda_count + 16'h0001;
                    end

                    if (scl_sync[SYNC_STAGES-1] == scl_filtered) begin
                        scl_count <= 16'h0000;
                    end else if (scl_count >= FILTER_LIMIT) begin
                        scl_filtered <= scl_sync[SYNC_STAGES-1];
                        scl_count    <= 16'h0000;
                    end else begin
                        scl_count <= scl_count + 16'h0001;
                    end
                end
            end
        end
    endgenerate

endmodule

// Repository status refresh: 2026-07-14
