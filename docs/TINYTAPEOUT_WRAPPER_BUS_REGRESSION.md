# Tiny Tapeout Wrapper Bus Regression

Date: 2026-07-11
Top module: `tt_um_shivamtiwari020505_i2c`
Simulator: Icarus Verilog 12.0
Status: PASS

## Commands Run

PowerShell runner:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\sim\run_wrapper_bus_regression.ps1
```

Shell runner under WSL:

```sh
bash sim/run_wrapper_bus_regression.sh
```

TinyTapeout cocotb harness under WSL:

```sh
cd test && make
```

## Observed Results

| Check | Status | Evidence |
| --- | --- | --- |
| Wrapper bus regression PowerShell runner | PASS | `ALL TINY TAPEOUT WRAPPER BUS REGRESSION TESTS PASSED` |
| Wrapper bus regression shell runner | PASS | `ALL TINY TAPEOUT WRAPPER BUS REGRESSION TESTS PASSED` |
| TinyTapeout cocotb harness | PASS | `TESTS=1 PASS=1 FAIL=0 SKIP=0` |
| Open-drain SDA/SCL bus model | PASS | `tb/tb_wrapper_top.sv` uses pullups and only drives low through `uio_oe`/`uio_out` or BFM pull-low controls. |
| `IRQ_CLEAR` pin | PASS | TC30 pulses `uio[6]` and observes `uio[5]` clear. |
| `WRAPPER_ERR` pin | PASS | TC30 deliberately reads empty RX FIFO and observes a `uio[7]` pulse. |

## Test Matrix

| Test | Status | Intent |
| --- | --- | --- |
| TC18-TT | PASS | DUT master writes an independent external slave BFM through the TT host pins. |
| TC19-TT | PASS | DUT master reads an independent external slave BFM through the TT host pins using repeated START. |
| TC20-TT | PASS | Independent external master BFM writes the DUT slave through TT SDA/SCL pins. |
| TC21-TT | PASS | Independent external master BFM reads the DUT slave through TT SDA/SCL pins. |
| TC22-TT | PASS | External slave BFM NACKs DUT master address and wrapper status reports ERROR. |
| TC23-TT | PASS | External slave BFM stretches SCL during a DUT master write. |
| TC24-TT | PASS | Stuck-low SCL prevents DUT master START and sets ERROR. |
| TC25-TT | PASS | External master BFM burst-writes four bytes into the DUT slave. |
| TC26-TT | PASS | External master BFM burst-reads four bytes from the DUT slave. |
| TC27-TT | PASS | External slave BFM NACKs a data byte and wrapper status reports ERROR. |
| TC28-TT | PASS | External master BFM STOP after pointer-only write does not overwrite DUT register data. |
| TC29-TT | PASS | Wrapper pin directions match the public pin map: control pins and `IRQ_CLEAR` are inputs, `IRQ` and `WRAPPER_ERR` are outputs. |
| TC30-TT | PASS | RX underflow pulses `WRAPPER_ERR`, latches IRQ, and `IRQ_CLEAR` clears IRQ. |

No fallback was used. The BFM-based wrapper bus regression is present and passing.