# SPDX-License-Identifier: Apache-2.0
import cocotb
from cocotb.triggers import ReadOnly, Timer

DATA_BASE = 0x10000000


@cocotb.test()
async def test_independent_memory_paths(dut):
    """Exercise the adapter against actual SRAM models, including error paths."""
    expected_data = [0x5A000000 + i for i in range(512)]
    dut.clk.value = 0
    dut.rst_n.value = 1
    dut.ena.value = 0
    await Timer(1, unit="ns")
    dut.rst_n.value = 0
    await Timer(1, unit="ns")

    async def step(*, fetch=None, address=None, write=False, value=0, be=15):
        old_valid = (int(dut.instr_rvalid.value), int(dut.data_rvalid.value))
        dut.instr_req.value = int(fetch is not None)
        dut.instr_addr.value = fetch if fetch is not None else 0
        dut.data_req.value = int(address is not None)
        dut.data_addr.value = address if address is not None else 0
        dut.data_we.value = int(write)
        dut.data_wdata.value = value
        dut.data_be.value = be
        await Timer(4, unit="ns")

        active = bool(int(dut.ena.value) and int(dut.rst_n.value))
        i_accept = active and fetch is not None
        d_accept = active and address is not None
        i_hit = fetch is not None and 0 <= fetch < 4096 and fetch % 4 == 0
        d_hit = (address is not None and DATA_BASE <= address < DATA_BASE + 2048
                 and address % 4 == 0)
        assert int(dut.instr_gnt.value) == i_accept
        assert int(dut.data_gnt.value) == d_accept
        assert int(dut.program_en.value) == (i_accept and i_hit)
        assert int(dut.data_mem_en.value) == (d_accept and d_hit)
        assert int(dut.program_we.value) == 0
        # Changing the request must not produce a combinational response.
        assert (int(dut.instr_rvalid.value), int(dut.data_rvalid.value)) == old_valid

        if d_accept and d_hit:
            index = (address - DATA_BASE) // 4
            if write:
                for byte in range(4):
                    if be & (1 << byte):
                        mask = 0xFF << (8 * byte)
                        expected_data[index] = ((expected_data[index] & ~mask)
                                                | (value & mask))
            expected_read = 0 if write else expected_data[index]
        else:
            expected_read = 0

        dut.clk.value = 1
        await Timer(1, unit="ns")
        assert int(dut.instr_rvalid.value) == i_accept
        assert int(dut.data_rvalid.value) == d_accept
        assert int(dut.instr_err.value) == (i_accept and not i_hit)
        assert int(dut.data_err.value) == (d_accept and not d_hit)
        assert int(dut.instr_rdata.value) == (0xA5000000 + fetch // 4
                                             if i_accept and i_hit else 0)
        assert int(dut.data_rdata.value) == expected_read
        dut.clk.value = 0
        await Timer(1, unit="ns")

    await step(fetch=0, address=DATA_BASE, write=True, value=0)
    dut.rst_n.value = 1
    # Disabled accesses cannot produce grants, reads, or writes.
    await step(fetch=0, address=DATA_BASE, write=True, value=0)
    dut.ena.value = 1

    # Both banks accept requests together, with no bubble between responses.
    for index in range(64):
        await step(fetch=index * 4, address=DATA_BASE + index * 4,
                   write=True, value=0x12340000 + index)
    for index in range(64):
        await step(fetch=(1023 - index) * 4, address=DATA_BASE + index * 4)

    # Address boundaries and byte masks, including a write with no enabled bytes.
    for address in (DATA_BASE, DATA_BASE + 2044):
        for be in (15, 1, 2, 4, 8, 5, 0):
            await step(fetch=4092, address=address, write=True,
                       value=0xABCD9876 ^ be, be=be)
            await step(fetch=0, address=address)

    # Wrong bank, out-of-range, and unaligned accesses return errors promptly.
    # In particular, invalid stores must not alias a valid SRAM word.
    for fetch in (4096, DATA_BASE, 0xFFFFFFFF, 2):
        await step(fetch=fetch, address=DATA_BASE)
    for address in (0, 4092, DATA_BASE + 2048, DATA_BASE + 4096,
                    0xFFFFFFFF, DATA_BASE + 2):
        await step(fetch=0, address=address)
        await step(fetch=4092, address=address, write=True, value=0)
    await step(fetch=0, address=DATA_BASE)
    await step(fetch=4092, address=DATA_BASE + 2044)

    # A response already in flight remains visible when ena drops.
    dut.ena.value = 0
    await Timer(1, unit="ns")
    assert int(dut.instr_rvalid.value) == 1
    assert int(dut.data_rvalid.value) == 1
    await step(fetch=0, address=DATA_BASE, write=True, value=0)
    dut.ena.value = 1
    await step(fetch=0, address=DATA_BASE)

    # Reset asynchronously cancels responses, but does not clear SRAM contents.
    dut.rst_n.value = 0
    await Timer(1, unit="ns")
    assert int(dut.instr_rvalid.value) == 0
    assert int(dut.data_rvalid.value) == 0
    assert int(dut.instr_gnt.value) == 0
    assert int(dut.data_gnt.value) == 0
    dut.rst_n.value = 1
    await step(fetch=0, address=DATA_BASE)
    await step()
    await ReadOnly()
