# APB I2C Master/Slave Core for Tiny Tapeout

[![GDS](https://github.com/shivamtiwari020505/i2c-ip-core-ttsky26c/actions/workflows/gds.yaml/badge.svg?branch=main)](https://github.com/shivamtiwari020505/i2c-ip-core-ttsky26c/actions/workflows/gds.yaml)
[![Docs](https://github.com/shivamtiwari020505/i2c-ip-core-ttsky26c/actions/workflows/docs.yaml/badge.svg?branch=main)](https://github.com/shivamtiwari020505/i2c-ip-core-ttsky26c/actions/workflows/docs.yaml)
[![Test](https://github.com/shivamtiwari020505/i2c-ip-core-ttsky26c/actions/workflows/test.yaml/badge.svg?branch=main)](https://github.com/shivamtiwari020505/i2c-ip-core-ttsky26c/actions/workflows/test.yaml)
[![FPGA](https://github.com/shivamtiwari020505/i2c-ip-core-ttsky26c/actions/workflows/fpga.yaml/badge.svg)](https://github.com/shivamtiwari020505/i2c-ip-core-ttsky26c/actions/workflows/fpga.yaml)

A synthesizable Verilog I2C master/slave controller packaged for the Tiny Tapeout TTSKY26c shuttle. The design keeps a reusable APB-style I2C core internally and exposes a compact byte-wide Tiny Tapeout host bridge at the `tt_um` boundary.

- Top module: `tt_um_shivamtiwari020505_i2c`
- Target shuttle: TTSKY26c / Sky130
- Clock: 50 MHz
- Tile size: `2x2`
- License: Apache-2.0

## Features

- I2C master and slave operation in one core
- FIFO-backed TX and RX data paths
- Byte-oriented Tiny Tapeout host interface
- Open-drain SDA/SCL split-I/O implementation for ASIC pads
- IRQ output plus explicit `IRQ_CLEAR` input
- `WRAPPER_ERR` pin for host-visible APB access errors
- Independent SystemVerilog BFMs for wrapper-level bus verification

## Tiny Tapeout Interface

| Signal | Direction | Description |
| --- | --- | --- |
| `ui_in[7:0]` | Input | Host write byte |
| `uo_out[7:0]` | Output | Last host read byte |
| `uio[0]` | Bidirectional | I2C SDA, open-drain low drive |
| `uio[1]` | Bidirectional | I2C SCL, open-drain low drive |
| `uio[2]` | Input | Write strobe |
| `uio[3]` | Input | Read strobe |
| `uio[4]` | Input | Register select: data path or command/status path |
| `uio[5]` | Output | IRQ |
| `uio[6]` | Input | `IRQ_CLEAR`, pulse high for one cycle |
| `uio[7]` | Output | `WRAPPER_ERR`, pulses on failed host register access |

The wrapper auto-configures the core after reset:

- Local slave address: `0x52`
- Master target address: `0x50`
- Core, master, slave, and IRQ enables asserted
- Prescaler left at the reset default for 50 MHz / 400 kHz operation

## Verification Status

| Flow | Status | Notes |
| --- | --- | --- |
| `test.yaml` | Passing | Tiny Tapeout cocotb smoke test |
| `docs.yaml` | Passing | Datasheet/documentation generation |
| `gds.yaml` | Passing | LibreLane hardening, precheck, GL test, and viewer deploy |
| `fpga.yaml` | Passing | Manually dispatched FPGA workflow |
| Wrapper bus regression | Passing | `tb/tb_wrapper_top.sv`, independent I2C master/slave BFMs |

Latest GDS run summary:

| Metric | Value |
| --- | --- |
| Tile count | `2x2` |
| Die area template | `0 0 334.88 225.76` |
| Final instance utilization | `45.9394%` |
| Core area | `72564.6` |
| Die area | `75602.5` |
| Reported violations | `0` |

Detailed wrapper regression results are in [docs/TINYTAPEOUT_WRAPPER_BUS_REGRESSION.md](docs/TINYTAPEOUT_WRAPPER_BUS_REGRESSION.md).

## Repository Layout

| Path | Purpose |
| --- | --- |
| `src/` | Synthesizable RTL and Tiny Tapeout top module |
| `test/` | Required Tiny Tapeout cocotb harness |
| `tb/` | SystemVerilog wrapper bus regression and I2C BFMs |
| `sim/` | Local wrapper regression runners |
| `docs/` | Public project documentation and regression report |
| `info.yaml` | Tiny Tapeout project metadata and pinout |

## Running Locally

Run the Tiny Tapeout cocotb smoke test:

```sh
cd test
make
```

Run the wrapper bus regression with Icarus:

```sh
bash sim/run_wrapper_bus_regression.sh
```

On Windows PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\sim\run_wrapper_bus_regression.ps1
```

## Documentation

- [Tiny Tapeout project documentation](docs/info.md)
- [Wrapper bus regression report](docs/TINYTAPEOUT_WRAPPER_BUS_REGRESSION.md)
- [GitHub Pages GDS viewer](https://shivamtiwari020505.github.io/i2c-ip-core-ttsky26c/)

## License

This project is released under the Apache License 2.0. See [LICENSE](LICENSE).

<!-- Repository status refresh: 2026-07-14 -->
