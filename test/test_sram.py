# SPDX-License-Identifier: Apache-2.0
import cocotb
from cocotb.triggers import ReadOnly, Timer


@cocotb.test()
async def test_sram_banks(dut):
    """Check actual PDK models through the hardware wrapper's public ports."""
    dut.clk.value = 0

    async def cycle():
        await Timer(5, unit="ns")
        dut.clk.value = 1
        await Timer(5, unit="ns")
        dut.clk.value = 0

    async def access(bank, address, *, write=False, value=0, be=15, enable=True):
        getattr(dut, f"{bank}_en").value = int(enable)
        getattr(dut, f"{bank}_we").value = int(write)
        getattr(dut, f"{bank}_be").value = be
        getattr(dut, f"{bank}_word_addr").value = address
        getattr(dut, f"{bank}_wdata").value = value
        await cycle()

    for bank, depth in (("program", 1024), ("data", 512)):
        dut._log.info("Checking %s SRAM: %d words", bank, depth)
        output = getattr(dut, f"{bank}_rdata")
        expected = [((a * 0x01010101) ^ 0xA5C0305A) & 0xFFFFFFFF
                    for a in range(depth)]
        # Fill first, then read the whole bank to detect address aliasing.
        for address, value in enumerate(expected):
            await access(bank, address, write=True, value=value)
        for address, value in enumerate(expected):
            await access(bank, address)
            assert int(output.value) == value, (bank, address)

        # Repeated reads and byte writes at both ends of the address range.
        for address in (0, depth - 1):
            for be in (1, 2, 4, 8, 5, 0):
                await access(bank, address, write=True, value=0x12345678, be=be)
                for byte in range(4):
                    if be & (1 << byte):
                        mask = 0xFF << (byte * 8)
                        expected[address] = ((expected[address] & ~mask)
                                             | (0x12345678 & mask))
                for _ in range(2):
                    await access(bank, address)
                    assert int(output.value) == expected[address], (bank, be)

        # Changing the address without a clock must not change read data.
        held = int(output.value)
        getattr(dut, f"{bank}_word_addr").value = 1
        await Timer(1, unit="ns")
        assert int(output.value) == held

        # Disabled reads hold the output; disabled writes leave memory intact.
        await access(bank, 1, enable=False)
        assert int(output.value) == held
        await access(bank, 1, write=True, value=0, enable=False)
        await access(bank, 1)
        assert int(output.value) == expected[1]
        getattr(dut, f"{bank}_en").value = 0

    # The two physical SRAMs must operate independently on the same edge.
    for bank, value in (("program", 0xCAFEBABE), ("data", 0xDEADBEEF)):
        getattr(dut, f"{bank}_en").value = 1
        getattr(dut, f"{bank}_we").value = 1
        getattr(dut, f"{bank}_be").value = 15
        getattr(dut, f"{bank}_word_addr").value = 7
        getattr(dut, f"{bank}_wdata").value = value
    await cycle()
    dut.program_we.value = 0
    dut.data_we.value = 0
    await cycle()
    # Let the final clock assignment settle before sampling and ending the test.
    await ReadOnly()
    assert int(dut.program_rdata.value) == 0xCAFEBABE
    assert int(dut.data_rdata.value) == 0xDEADBEEF
