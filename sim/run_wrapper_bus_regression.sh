#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build

rtl=(
  src/clk_divider.v
  src/apb_slave_if.v
  src/sync_fifo.v
  src/reg_file.v
  src/i2c_master_fsm.v
  src/i2c_slave_fsm.v
  src/i2c_line_filter.v
  src/i2c_top_split_io.v
  src/tt_um_shivamtiwari020505_i2c.v
)

sim_out=build/tinytapeout_wrapper_bus_regression.vvp
iverilog -g2012 -Wall -o "$sim_out" -I src/ \
  "${rtl[@]}" \
  tb/i2c_master_bfm.sv tb/i2c_slave_bfm.sv tb/tb_wrapper_top.sv
vvp "$sim_out"