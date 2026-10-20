# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.triggers import ReadOnly, Timer


@cocotb.test()
async def test_cpu_sram_execution(dut):
    """Boot the actual RV32EC core and observe its data-memory transactions."""
    dut.clk.value = 0
    dut.rst_n.value = 0
    dut.ena.value = 0
    dut.ui_in.value = 0
    dut.uio_in.value = 0

    async def tick():
        await Timer(5, unit="ns")
        dut.clk.value = 1
        await Timer(5, unit="ns")
        dut.clk.value = 0
        await Timer(1, unit="ns")

    async def observe(selector):
        dut.uio_in.value = selector << 4
        await Timer(1, unit="ns")
        return int(dut.uo_out.value)

    for _ in range(4):
        await tick()
    dut.rst_n.value = 1
    dut.ena.value = 1

    expected = [
        # address, write, byte enables, meaningful write-data bits
        (0x10000000, True, 15, 0x00000123),
        (0x10000000, False, 15, None),
        (0x10000004, True, 15, 0x00000124),
        (0x10000004, True, 2, 0x0000AB00),
        (0x10000004, False, 2, None),
        (0x10000004, True, 12, 0x00AC0000),
        (0x10000008, True, 15, 0x0000600D),
    ]
    transaction = 0
    parallel_access_seen = False
    slept = False
    for _ in range(300):
        status = await observe(12)
        handshakes = await observe(14)
        assert await observe(13) == 0, "Ibex reported a fault/alert"
        assert handshakes & 0x30 == 0, "Unexpected SRAM access error"
        if status & 2:  # data_req
            assert handshakes & 2, "Data access was stalled"
            address = sum([(await observe(4 + byte)) << (byte * 8)
                           for byte in range(4)])
            write = bool(status & 4)
            be = (status >> 3) & 15
            assert transaction < len(expected), "Unexpected extra data transaction"
            want_address, want_write, want_be, want_data = expected[transaction]
            assert (address, write, be) == (want_address, want_write, want_be)
            if write:
                value = sum([(await observe(8 + byte)) << (byte * 8)
                             for byte in range(4)])
                mask = sum(0xFF << (8 * byte) for byte in range(4) if be & (1 << byte))
                assert value & mask == want_data
            parallel_access_seen |= bool(handshakes & 1)
            transaction += 1
        if transaction == len(expected) and status & 0x80:  # WFI after completion
            slept = True
            break
        await tick()

    assert slept, "CPU did not reach WFI before the cycle limit"
    assert transaction == len(expected)
    assert parallel_access_seen, "No simultaneous instruction/data request observed"
    assert int(dut.uio_oe.value) == 0
    assert int(dut.uio_out.value) == 0
    await ReadOnly()
