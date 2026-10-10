# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer


BIT_CLOCKS = 104
BIT_NS = BIT_CLOCKS * 1000
TX_READY = 1 << 1
RX_VALID = 1 << 2
FIFO_FULL = 1 << 4
RX_ERROR = 1 << 5
TX_IDLE = (1 << 6) | TX_READY


async def tick(dut, count=1):
    await ClockCycles(dut.clk, count)
    await Timer(1, unit="ns")


class Inputs:
    """Let concurrent TX/RX drivers update their own input pins."""

    def __init__(self, dut):
        self.dut = dut
        self.value = 0x80  # RX idle high, both parallel requests low.
        dut.uio_in.value = self.value

    def set(self, *, rx=None, valid=None, ready=None):
        for bit, value in ((7, rx), (0, valid), (3, ready)):
            if value is not None:
                self.value = (self.value & ~(1 << bit)) | (value << bit)
        self.dut.uio_in.value = self.value


async def setup(dut):
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.rst_n.value = 0
    pins = Inputs(dut)
    cocotb.start_soon(Clock(dut.clk, 1, unit="us").start())
    await tick(dut, 5)
    dut.rst_n.value = 1
    await tick(dut, 5)
    assert int(dut.uio_oe.value) == 0x76
    assert int(dut.uio_out.value) == TX_IDLE
    assert int(dut.uo_out.value) == 0
    return pins


async def transmit(pins, value, *, request_while_busy=False):
    dut = pins.dut
    assert int(dut.uio_out.value) & TX_READY
    dut.ui_in.value = value
    pins.set(valid=1)
    await tick(dut)
    pins.set(valid=0)

    frame = [0] + [(value >> bit) & 1 for bit in range(8)] + [1]
    elapsed = 0
    for expected_bit in frame:
        for _ in range(BIT_CLOCKS):
            outputs = int(dut.uio_out.value)
            assert (outputs >> 6) & 1 == expected_bit, f"TX timing at clock {elapsed}"
            assert outputs & TX_READY == 0, "TX ready before stop bit finished"
            if request_while_busy and elapsed == 200:
                dut.ui_in.value = value ^ 0xFF
                pins.set(valid=1)
            elif request_while_busy and elapsed == 203:
                pins.set(valid=0)
            await tick(dut)
            elapsed += 1

    assert int(dut.uio_out.value) & TX_IDLE == TX_IDLE
    await tick(dut, 3)
    assert int(dut.uio_out.value) & TX_IDLE == TX_IDLE


async def receive(pins, value, *, phase_ns=137, stop=1, bit_ns=BIT_NS):
    dut = pins.dut
    previous = int(dut.uo_out.value)
    await Timer(phase_ns, unit="ns")
    pins.set(rx=0)
    await Timer(bit_ns, unit="ns")
    for bit in range(8):
        pins.set(rx=(value >> bit) & 1)
        await Timer(bit_ns, unit="ns")
    pins.set(rx=stop)
    await Timer(bit_ns // 4, unit="ns")
    assert int(dut.uo_out.value) == previous, "Published an incomplete frame"
    await Timer(bit_ns - bit_ns // 4, unit="ns")
    pins.set(rx=1)
    # The consumer is stalled in these tests, so a queued head must stay put.
    if not stop:
        assert int(dut.uo_out.value) == previous


async def take(pins, expected):
    """Accept exactly one byte on the next rising clock edge."""
    dut = pins.dut
    assert int(dut.uio_out.value) & RX_VALID
    assert int(dut.uo_out.value) == expected
    pins.set(ready=1)
    await tick(dut)
    pins.set(ready=0)


def assert_empty(dut):
    assert int(dut.uio_out.value) & (RX_VALID | FIFO_FULL) == 0
    assert int(dut.uo_out.value) == 0


@cocotb.test()
async def full_duplex_and_busy_requests(dut):
    pins = await setup(dut)
    values = (0x00, 0xFF, 0x55, 0xAA, 0x01, 0x80, 0xA5, 0x3C)
    for index, value in enumerate(values):
        rx_task = cocotb.start_soon(receive(pins, value ^ 0x69, phase_ns=137 + index * 83))
        await transmit(pins, value, request_while_busy=True)
        await rx_task
        await take(pins, value ^ 0x69)
        assert_empty(dut)
        assert int(dut.uio_out.value) & RX_ERROR == 0


@cocotb.test()
async def back_to_back_rx_and_baud_offset(dut):
    pins = await setup(dut)
    for bit_ns in (BIT_NS, 103_000, 105_000):
        for value in (0x55, 0xA5, 0x00, 0xFF):
            await receive(pins, value, phase_ns=1, bit_ns=bit_ns)
        for value in (0x55, 0xA5, 0x00, 0xFF):
            await take(pins, value)
        assert_empty(dut)
    assert int(dut.uio_out.value) & RX_ERROR == 0


@cocotb.test()
async def false_start_and_framing_error(dut):
    pins = await setup(dut)
    pins.set(rx=0)
    await Timer(10_000, unit="ns")
    pins.set(rx=1)
    await Timer(BIT_NS * 2, unit="ns")
    assert int(dut.uo_out.value) == 0
    assert int(dut.uio_out.value) & RX_ERROR == 0

    await receive(pins, 0x3C)
    await receive(pins, 0xA5, stop=0)
    assert int(dut.uio_out.value) & RX_ERROR
    await take(pins, 0x3C)
    assert_empty(dut)  # Invalid frame must not enter the FIFO.
    # Allow the line to return to idle after the invalid stop bit.
    await Timer(BIT_NS * 2, unit="ns")
    await receive(pins, 0x96)
    await take(pins, 0x96)
    assert int(dut.uio_out.value) & RX_ERROR, "Error should stay set until reset"
    dut.rst_n.value = 0
    await tick(dut, 3)
    assert int(dut.uio_out.value) == TX_IDLE
    assert int(dut.uo_out.value) == 0


@cocotb.test()
async def sustained_low_recovery(dut):
    pins = await setup(dut)
    # Vary the release time: without RECOVER, a new frame attempt could be
    # partway through its data bits when the held-low line returns high.
    for low_clocks, value in ((14 * BIT_CLOCKS + 17, 0xA5),
                              (25 * BIT_CLOCKS + 53, 0x3C),
                              (40 * BIT_CLOCKS + 91, 0x96)):
        pins.set(rx=0)
        for _ in range(low_clocks):
            await tick(dut)
            assert_empty(dut)
        assert int(dut.uio_out.value) & RX_ERROR, "Missing stop bit must flag an error"

        pins.set(rx=1)
        # Allow even a stale frame attempt enough time to finish. Keep the
        # consumer stalled so any bogus byte remains visible in the FIFO.
        for _ in range(11 * BIT_CLOCKS):
            await tick(dut)
            assert_empty(dut)

        await receive(pins, value)
        await take(pins, value)
        await tick(dut, 2)
        assert_empty(dut)  # Exactly one byte was queued.
        assert int(dut.uio_out.value) & RX_ERROR, "Recovery must not clear the sticky error"


@cocotb.test()
async def reset_during_full_duplex(dut):
    pins = await setup(dut)
    dut.ui_in.value = 0x55
    pins.set(valid=1, rx=0)
    await tick(dut)
    pins.set(valid=0)
    await tick(dut, 200)
    dut.rst_n.value = 0
    pins.set(rx=1)
    await tick(dut, 3)
    assert int(dut.uio_out.value) == TX_IDLE
    assert int(dut.uo_out.value) == 0
    dut.rst_n.value = 1
    await tick(dut, 5)
    rx_task = cocotb.start_soon(receive(pins, 0xA5))
    await transmit(pins, 0x3C)
    await rx_task
    await take(pins, 0xA5)
    assert_empty(dut)


@cocotb.test()
async def fifo_stalls_overflow_and_wraparound(dut):
    pins = await setup(dut)
    values = [0x30 + index for index in range(8)]
    for index, value in enumerate(values):
        await receive(pins, value)
        assert int(dut.uio_out.value) & RX_VALID
        assert int(dut.uo_out.value) == values[0]
        assert bool(int(dut.uio_out.value) & FIFO_FULL) == (index == 7)
    await tick(dut, 20)
    assert int(dut.uo_out.value) == values[0]

    await receive(pins, 0xEE)  # Ninth byte is dropped; unread bytes survive.
    assert int(dut.uio_out.value) & (FIFO_FULL | RX_ERROR) == FIFO_FULL | RX_ERROR
    for value in values:
        await take(pins, value)
    assert_empty(dut)

    for index in range(12):  # Exercise both pointers through multiple wraps.
        await receive(pins, index)
        await take(pins, index)
        assert_empty(dut)

    await receive(pins, 0xA5)
    dut.rst_n.value = 0
    await tick(dut, 3)
    assert int(dut.uio_out.value) == TX_IDLE
    assert_empty(dut)


@cocotb.test()
async def continuous_rx_ready(dut):
    pins = await setup(dut)
    values = [0xA5, 0x3C, 0x00, 0xFF, 0x96]

    async def consume():
        pins.set(ready=1)
        accepted = []
        for _ in range(len(values) * BIT_CLOCKS * 11):
            if int(dut.uio_out.value) & RX_VALID:
                accepted.append(int(dut.uo_out.value))
            await tick(dut)
            if len(accepted) == len(values):
                pins.set(ready=0)
                assert accepted == values
                return
        assert False, f"Timed out: accepted {accepted}"

    consumer = cocotb.start_soon(consume())
    for value in values:
        # No stalled-output assertions while the consumer is actively draining.
        await Timer(137, unit="ns")
        for bit in [0] + [(value >> n) & 1 for n in range(8)] + [1]:
            pins.set(rx=bit)
            await Timer(BIT_NS, unit="ns")
    await consumer
    assert_empty(dut)
    assert int(dut.uio_out.value) & RX_ERROR == 0
