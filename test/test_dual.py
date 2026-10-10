"""Starter bench: two real UARTs connected through their serial pins.

Python acts as the parallel producer/consumer at each end. It never drives RX
or constructs serial frames here; the other DUT does that work.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer


async def tick(dut, count=1):
    await ClockCycles(dut.clk, count)
    # Sample after the HDL's nonblocking assignments and combinational updates.
    await Timer(1, unit="ns")


async def wait_high(dut, signal, limit=1200):
    # A frame takes 1040 clocks. A bounded wait turns a broken DUT into a test
    # failure instead of a simulation that runs forever.
    for _ in range(limit):
        if int(signal.value) == 1:
            return
        await tick(dut)
    raise AssertionError(f"Timed out waiting for {signal._name}")


async def send_byte(dut, data, valid, ready, value):
    await wait_high(dut, ready)
    data.value = value
    valid.value = 1
    await tick(dut)  # The next rising edge accepts this parallel byte.
    valid.value = 0
    # TX continues serializing after this function returns.


async def read_byte(dut, data, valid, ready):
    await wait_high(dut, valid)
    value = int(data.value)  # Read the current head BEFORE requesting its pop.
    ready.value = 1
    await tick(dut)  # This edge removes the byte from the receiver's FIFO.
    ready.value = 0
    return value


@cocotb.test()
async def one_byte_each_way(dut):
    # Initialize every input before starting the clock.
    dut.clk.value = 0
    dut.rst_n.value = 0
    dut.ena.value = 1
    dut.a_tx_data.value = 0
    dut.b_tx_data.value = 0
    dut.a_tx_valid.value = 0
    dut.b_tx_valid.value = 0
    dut.a_rx_ready.value = 0
    dut.b_rx_ready.value = 0
    cocotb.start_soon(Clock(dut.clk, 1, unit="us").start())
    await tick(dut, 5)
    dut.rst_n.value = 1
    await tick(dut, 5)

    assert int(dut.a_tx.value) == int(dut.b_tx.value) == 1
    assert int(dut.a_rx_valid.value) == int(dut.b_rx_valid.value) == 0
    assert int(dut.a_uio_oe.value) == int(dut.b_uio_oe.value) == 0x76

    # Full path: A parallel input -> A TX -> B RX -> B FIFO -> B parallel output.
    await send_byte(dut, dut.a_tx_data, dut.a_tx_valid, dut.a_tx_ready, 0xA5)
    received = await read_byte(dut, dut.b_rx_data, dut.b_rx_valid, dut.b_rx_ready)
    assert received == 0xA5, f"B received {received:#04x}"

    # Reverse direction through the other cross-connection.
    await send_byte(dut, dut.b_tx_data, dut.b_tx_valid, dut.b_tx_ready, 0x3C)
    received = await read_byte(dut, dut.a_rx_data, dut.a_rx_valid, dut.a_rx_ready)
    assert received == 0x3C, f"A received {received:#04x}"
    # RX publishes at the stop-bit center, before the sender finishes that bit.
    # Let both TX engines finish and the final ready deassertion take effect.
    await wait_high(dut, dut.a_tx_ready)
    await wait_high(dut, dut.b_tx_ready)
    await tick(dut)
    assert int(dut.a_rx_error.value) == int(dut.b_rx_error.value) == 0
    assert int(dut.a_rx_valid.value) == int(dut.b_rx_valid.value) == 0

    # Try 0x00, 0xFF, 0x55, 0xAA and check a whole sequence in order.
    # Offer bytes on A and B concurrently with cocotb.start_soon(...).
@cocotb.test()
async def concurrent_transmission(dut):
    # Initialize every input before starting the clock.
    dut.clk.value = 0
    dut.rst_n.value = 0
    dut.ena.value = 1
    dut.a_tx_data.value = 0
    dut.b_tx_data.value = 0
    dut.a_tx_valid.value = 0
    dut.b_tx_valid.value = 0
    dut.a_rx_ready.value = 1
    dut.b_rx_ready.value = 1
    cocotb.start_soon(Clock(dut.clk, 1, unit="us").start())
    await tick(dut, 5)
    dut.rst_n.value = 1
    await tick(dut, 5)

    assert int(dut.a_tx.value) == int(dut.b_tx.value) == 1
    assert int(dut.a_rx_valid.value) == int(dut.b_rx_valid.value) == 0
    assert int(dut.a_uio_oe.value) == int(dut.b_uio_oe.value) == 0x76

    dataA = [0x3C, 0xFF, 0x55, 0xAA, 0xA5]
    dataB = [0xA5, 0xAA, 0x55, 0xFF, 0x3C]

    for dA, dB in zip(dataA, dataB):
        await send_byte(dut, dut.a_tx_data, dut.a_tx_valid, dut.a_tx_ready, dA)
        await send_byte(dut, dut.b_tx_data, dut.b_tx_valid, dut.b_tx_ready, dB)

        receivedA = await read_byte(dut, dut.b_rx_data, dut.b_rx_valid, dut.b_rx_ready)
        receivedB = await read_byte(dut, dut.a_rx_data, dut.a_rx_valid, dut.a_rx_ready)

        assert receivedA == dA, f"B received {receivedA:#04x}"
        assert receivedB == dB, f"A received {receivedB:#04x}"

    # RX publishes at the stop-bit center, before the sender finishes that bit.
    # Let both TX engines finish and the final ready deassertion take effect.
    await wait_high(dut, dut.a_tx_ready)
    await wait_high(dut, dut.b_tx_ready)
    await tick(dut)
    assert int(dut.a_rx_error.value) == int(dut.b_rx_error.value) == 0
    assert int(dut.a_rx_valid.value) == int(dut.b_rx_valid.value) == 0

# Keep one RX_READY low, send several bytes, then drain that FIFO.
@cocotb.test()
async def fill_fifo(dut):
    # Initialize every input before starting the clock.
    dut.clk.value = 0
    dut.rst_n.value = 0
    dut.ena.value = 1
    dut.a_tx_data.value = 0
    dut.b_tx_data.value = 0
    dut.a_tx_valid.value = 0
    dut.b_tx_valid.value = 0
    dut.a_rx_ready.value = 0
    dut.b_rx_ready.value = 0
    cocotb.start_soon(Clock(dut.clk, 1, unit="us").start())
    await tick(dut, 5)
    dut.rst_n.value = 1
    await tick(dut, 5)

    assert int(dut.a_tx.value) == int(dut.b_tx.value) == 1
    assert int(dut.a_rx_valid.value) == int(dut.b_rx_valid.value) == 0
    assert int(dut.a_uio_oe.value) == int(dut.b_uio_oe.value) == 0x76

    dataA = [0x3C, 0xFF, 0x55, 0xAA, 0xA5, 0x00, 0x01, 0xF1]
    dataB = [0xA5, 0xAA, 0x55, 0xFF, 0x3C, 0x00, 0x01, 0xF1]

    for dA, dB in zip(dataA, dataB):
        await send_byte(dut, dut.a_tx_data, dut.a_tx_valid, dut.a_tx_ready, dA)
        await send_byte(dut, dut.b_tx_data, dut.b_tx_valid, dut.b_tx_ready, dB)

    await wait_high(dut, dut.a_tx_ready)
    await wait_high(dut, dut.b_tx_ready)
    await tick(dut)

    assert int(dut.a_fifo_full.value) == int(dut.b_fifo_full.value) == 1
    assert int(dut.a_rx_error.value) == int(dut.b_rx_error.value) == 0

    for i in range(8):
        receivedA = await read_byte(dut, dut.b_rx_data, dut.b_rx_valid, dut.b_rx_ready)
        receivedB = await read_byte(dut, dut.a_rx_data, dut.a_rx_valid, dut.a_rx_ready)

        assert receivedA == dataA[i], f"B received {receivedA:#04x}"
        assert receivedB == dataB[i], f"A received {receivedB:#04x}"

    # RX publishes at the stop-bit center, before the sender finishes that bit.
    # Let both TX engines finish and the final ready deassertion take effect.
    await wait_high(dut, dut.a_tx_ready)
    await wait_high(dut, dut.b_tx_ready)
    await tick(dut)
    assert int(dut.a_rx_error.value) == int(dut.b_rx_error.value) == 0
    assert int(dut.a_rx_valid.value) == int(dut.b_rx_valid.value) == 0

# Fill eight entries, send a ninth byte, and check full/error behavior.
@cocotb.test()
async def overflow_fifo(dut):
    # Initialize every input before starting the clock.
    dut.clk.value = 0
    dut.rst_n.value = 0
    dut.ena.value = 1
    dut.a_tx_data.value = 0
    dut.b_tx_data.value = 0
    dut.a_tx_valid.value = 0
    dut.b_tx_valid.value = 0
    dut.a_rx_ready.value = 0
    dut.b_rx_ready.value = 0
    cocotb.start_soon(Clock(dut.clk, 1, unit="us").start())
    await tick(dut, 5)
    dut.rst_n.value = 1
    await tick(dut, 5)

    assert int(dut.a_tx.value) == int(dut.b_tx.value) == 1
    assert int(dut.a_rx_valid.value) == int(dut.b_rx_valid.value) == 0
    assert int(dut.a_uio_oe.value) == int(dut.b_uio_oe.value) == 0x76

    dataA = [0x3C, 0xFF, 0x55, 0xAA, 0xA5, 0x00, 0x01, 0xF1, 0xDE]
    dataB = [0xA5, 0xAA, 0x55, 0xFF, 0x3C, 0x00, 0x01, 0xF1, 0xAD]

    for dA, dB in zip(dataA, dataB):
        await tick(dut)
        await send_byte(dut, dut.a_tx_data, dut.a_tx_valid, dut.a_tx_ready, dA)
        await send_byte(dut, dut.b_tx_data, dut.b_tx_valid, dut.b_tx_ready, dB)

    await wait_high(dut, dut.a_tx_ready)
    await wait_high(dut, dut.b_tx_ready)
    await tick(dut)

    assert int(dut.a_fifo_full.value) == int(dut.b_fifo_full.value) == 1
    assert int(dut.a_rx_error.value) == int(dut.b_rx_error.value) == 1

    for i in range(8):
        receivedA = await read_byte(dut, dut.b_rx_data, dut.b_rx_valid, dut.b_rx_ready)
        receivedB = await read_byte(dut, dut.a_rx_data, dut.a_rx_valid, dut.a_rx_ready)

        assert receivedA == dataA[i], f"B received {receivedA:#04x}"
        assert receivedB == dataB[i], f"A received {receivedB:#04x}"

    # RX publishes at the stop-bit center, before the sender finishes that bit.
    # Let both TX engines finish and the final ready deassertion take effect.
    await wait_high(dut, dut.a_tx_ready)
    await wait_high(dut, dut.b_tx_ready)
    await tick(dut)
    assert int(dut.a_rx_error.value) == int(dut.b_rx_error.value) == 1 # sticky
    assert int(dut.a_rx_valid.value) == int(dut.b_rx_valid.value) == 0

    # TODO: Assert reset during transmission and check recovery.
