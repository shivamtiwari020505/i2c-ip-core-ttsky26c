# SPDX-FileCopyrightText: 2026 shivamtiwari020505
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles


SDA_SCL_HIGH = 0x03
WR_STROBE = 1 << 2
RD_STROBE = 1 << 3
REG_SEL = 1 << 4
IRQ_PIN = 1 << 5
IRQ_CLEAR = 1 << 6
ERR_PIN = 1 << 7


def uio_out_int(dut):
    return int(dut.uio_out.value)


async def set_uio(dut, *, reg_sel=0, wr=0, rd=0, irq_clear=0):
    value = SDA_SCL_HIGH
    if wr:
        value |= WR_STROBE
    if rd:
        value |= RD_STROBE
    if reg_sel:
        value |= REG_SEL
    if irq_clear:
        value |= IRQ_CLEAR
    dut.uio_in.value = value
    await ClockCycles(dut.clk, 1)


async def wrapper_write(dut, reg_sel, data):
    dut.ui_in.value = data
    await set_uio(dut, reg_sel=reg_sel, wr=0, rd=0)
    await set_uio(dut, reg_sel=reg_sel, wr=1, rd=0)
    await set_uio(dut, reg_sel=reg_sel, wr=0, rd=0)
    await ClockCycles(dut.clk, 4)


async def wrapper_read(dut, reg_sel):
    data, _seen_uio = await wrapper_read_capture_uio(dut, reg_sel)
    return data


async def wrapper_read_capture_uio(dut, reg_sel):
    seen_uio = uio_out_int(dut)
    await set_uio(dut, reg_sel=reg_sel, wr=0, rd=0)
    seen_uio |= uio_out_int(dut)
    await set_uio(dut, reg_sel=reg_sel, wr=0, rd=1)
    seen_uio |= uio_out_int(dut)
    await set_uio(dut, reg_sel=reg_sel, wr=0, rd=0)
    seen_uio |= uio_out_int(dut)
    for _ in range(8):
        await ClockCycles(dut.clk, 1)
        seen_uio |= uio_out_int(dut)
    return int(dut.uo_out.value), seen_uio


async def pulse_irq_clear(dut):
    await set_uio(dut, irq_clear=0)
    await set_uio(dut, irq_clear=1)
    await set_uio(dut, irq_clear=0)
    await ClockCycles(dut.clk, 6)


@cocotb.test()
async def test_tt_i2c_wrapper_smoke(dut):
    dut._log.info("Start tt_um_shivamtiwari020505_i2c smoke test")

    clock = Clock(dut.clk, 20, unit="ns")
    cocotb.start_soon(clock.start())

    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = SDA_SCL_HIGH
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 40)

    uio_oe = int(dut.uio_oe.value)
    assert (uio_oe & (IRQ_PIN | ERR_PIN)) == (IRQ_PIN | ERR_PIN), (
        "IRQ uio[5] and WRAPPER_ERR uio[7] must be output-enabled"
    )
    assert (uio_oe & (WR_STROBE | RD_STROBE | REG_SEL | IRQ_CLEAR)) == 0, (
        "host control and IRQ_CLEAR uio pins must remain input-only"
    )

    status = await wrapper_read(dut, reg_sel=1)
    assert (status & 0x80) == 0, f"unexpected ERROR after reset/init: status=0x{status:02x}"
    assert (status & 0x08) == 0x08, f"TX_EMPTY should be set after reset/init: status=0x{status:02x}"

    _rx_data, seen_uio = await wrapper_read_capture_uio(dut, reg_sel=0)
    assert (seen_uio & ERR_PIN) == ERR_PIN, "WRAPPER_ERR uio[7] should pulse on RX underflow"
    await ClockCycles(dut.clk, 2)
    assert (uio_out_int(dut) & IRQ_PIN) == IRQ_PIN, "IRQ uio[5] should latch after RX underflow"

    await pulse_irq_clear(dut)
    assert (uio_out_int(dut) & IRQ_PIN) == 0, "IRQ_CLEAR uio[6] pulse should clear IRQ uio[5]"

    status = await wrapper_read(dut, reg_sel=1)
    assert (status & 0x80) == 0, f"IRQ_CLEAR should clear ERROR status: status=0x{status:02x}"

    await wrapper_write(dut, reg_sel=0, data=0x5A)
    status = await wrapper_read(dut, reg_sel=1)
    assert (status & 0x08) == 0, f"TX_EMPTY should clear after TX_DATA write: status=0x{status:02x}"
    assert (status & 0x80) == 0, f"TX_DATA write should not set ERROR: status=0x{status:02x}"

    dut._log.info("tt_um_shivamtiwari020505_i2c smoke test passed")
