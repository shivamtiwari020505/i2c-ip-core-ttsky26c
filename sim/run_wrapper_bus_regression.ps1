$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")
New-Item -ItemType Directory -Force -Path "build" | Out-Null

$rtl = @(
  "src/clk_divider.v",
  "src/apb_slave_if.v",
  "src/sync_fifo.v",
  "src/reg_file.v",
  "src/i2c_master_fsm.v",
  "src/i2c_slave_fsm.v",
  "src/i2c_line_filter.v",
  "src/i2c_top_split_io.v",
  "src/tt_um_shivamtiwari020505_i2c.v"
)

$simOut = "build/tinytapeout_wrapper_bus_regression.vvp"
$ivArgs = @("-g2012", "-Wall", "-o", $simOut, "-I", "src/") + $rtl + @(
  "tb/i2c_master_bfm.sv",
  "tb/i2c_slave_bfm.sv",
  "tb/tb_wrapper_top.sv"
)

& iverilog @ivArgs
if ($LASTEXITCODE -ne 0) {
  throw "wrapper bus regression iverilog failed with exit code $LASTEXITCODE"
}

& vvp $simOut
if ($LASTEXITCODE -ne 0) {
  throw "wrapper bus regression vvp failed with exit code $LASTEXITCODE"
}
# Repository status refresh: 2026-07-14
