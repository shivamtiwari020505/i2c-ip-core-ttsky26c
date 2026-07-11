## How it works

This project contains a byte-hosted I2C master/slave controller. Internally it keeps the full APB I2C IP core: master FSM, slave FSM, TX/RX FIFOs, register file, line filter, IRQ/status/error handling, and clock-stretch support. The Tiny Tapeout wrapper compresses the APB host side into a small strobe interface so the design fits the standard `tt_um` pin budget.

The wrapper auto-configures the core after reset:

- Local slave address: `0x52`
- Master target address: `0x50`
- Core, master, slave, and IRQ enable bits set
- Prescaler left at the core reset default for the 50 MHz / 400 kHz timing-safe configuration

`uio[0]` is I2C SDA and `uio[1]` is I2C SCL. Both use open-drain behavior: the design only drives low and otherwise releases the line, so external pull-ups are required.

The host byte interface is:

- `ui_in[7:0]`: host write byte
- `uo_out[7:0]`: last host read byte
- `uio[2]`: write strobe
- `uio[3]`: read strobe
- `uio[4]`: register select, `0` for data path and `1` for command/status path
- `uio[5]`: IRQ output
- `uio[6]`: IRQ clear input; pulse `uio[6]` high for one cycle to clear all latched IRQ sources
- `uio[7]`: wrapper APB error output; pulses high for one cycle whenever the last host-triggered register access got a `PSLVERR`

When `REG_SEL=0`, a write strobe pushes `ui_in` into the TX FIFO. A read strobe pops one byte from RX FIFO and places it on `uo_out` after the internal APB access completes.

When `REG_SEL=1`, a write strobe writes the command byte. Command bits are START bit 0, STOP bit 1, READ bit 2, WRITE bit 3, and REPEATED_START bit 4. A read strobe returns the low status byte on `uo_out`: BUS_BUSY, ACK_RX, ARB_LOST, TX_EMPTY, RX_VALID, TX_FULL, RX_FULL, ERROR.

## How to test

Clock the design at 50 MHz and hold `rst_n` low for at least 10 clocks. Keep `uio_in[0]` and `uio_in[1]` high in simulation to model released I2C pull-ups unless an external I2C model is actively pulling a line low.

Basic host smoke test:

1. Reset the design and wait for auto-configuration.
2. Read status using `REG_SEL=1` and `RD_STROBE`; `TX_EMPTY` should be set and `ERROR` should be clear.
3. Write one byte using `REG_SEL=0` and `WR_STROBE`; this pushes the TX FIFO.
4. Read status again; `TX_EMPTY` should now be clear.

The source repository includes a SystemVerilog/Icarus wrapper bus regression in `tb/tb_wrapper_top.sv`, runnable with `sim/run_wrapper_bus_regression.ps1` or `sim/run_wrapper_bus_regression.sh`. It drives this wrapper through the TT pins, models real open-drain SDA/SCL pull-ups, and reuses independent I2C master/slave BFMs for write, read, burst, repeated-START, NACK, clock-stretch, stuck-bus, pointer-only STOP, `WRAPPER_ERR`, and `IRQ_CLEAR` cases. See `docs/TINYTAPEOUT_WRAPPER_BUS_REGRESSION.md` for the latest local run results.

## External hardware

External pull-up resistors are required on SDA and SCL. For a real demo, connect `uio[0]`/SDA and `uio[1]`/SCL to a 3.3 V I2C target such as an EEPROM, sensor, or MCU I2C peripheral, subject to the Tiny Tapeout demo board voltage and pad-use guidance.
