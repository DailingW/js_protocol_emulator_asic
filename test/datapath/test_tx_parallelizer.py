"""TX ready/valid contract tests; intentionally fail on broken RTL.

These tests check stream control and the registered uio_out pad output.
Pad data is sampled after the launch edge, including output-enable masking.
They never patch the DUT, force internals, or mark failures as expected.
"""

import random

import cocotb

from stream_tb import IDENTITY, REVERSED, SCRAMBLED, StreamBench, mapped_bits, stream_tx


@cocotb.test()
async def reset_idle_and_disable(dut):
    bench = StreamBench(dut, "tx")
    for width in range(1, 9):
        await bench.reset(width)
        for ready in (0, 1, 0):
            await bench.step(ready=ready)
        for _ in range(3):
            transfer = await bench.step(valid=1, data=1, enabled=0)
            assert not transfer.accepted and not transfer.emitted
        await stream_tx(bench, [0, 1] * width)


@cocotb.test()
async def exhaustive_widths_pad_patterns_and_maps(dut):
    bench = StreamBench(dut, "tx")
    for width in range(1, 9):
        for mapping in (IDENTITY, REVERSED, SCRAMBLED):
            await bench.reset(width, mapping)
            bits = [bit for word in range(256) for bit in mapped_bits(word, width, mapping)]
            await stream_tx(bench, bits)


@cocotb.test()
async def sustained_traffic_has_no_interframe_bubbles(dut):
    bench = StreamBench(dut, "tx")
    for width in range(1, 9):
        await bench.reset(width, SCRAMBLED)
        bits = [
            bit
            for word in [0xA5, 0x5A, 0x00, 0xFF] * 16
            for bit in mapped_bits(word, width, SCRAMBLED)
        ]
        # Checks readiness on every collecting cycle, exact completion after
        # N accepted bits, and simultaneous dequeue / next-frame first bit.
        await stream_tx(bench, bits)


@cocotb.test()
async def source_gaps_before_every_lane_do_not_advance_collection(dut):
    bench = StreamBench(dut, "tx")
    for width in range(1, 9):
        for gap_lane in range(width):
            await bench.reset(width, REVERSED)
            for word in (0xA5, 0x5A, 0xFF, 0x00):
                for lane, bit in enumerate(mapped_bits(word, width, REVERSED)):
                    if lane == gap_lane:
                        for noise in (1, 0, 1, 0):
                            # Invalid input data must never count as a bit.
                            transfer = await bench.step(data=noise)
                            assert not transfer.accepted
                    transfer = await bench.step(valid=1, data=bit)
                    assert transfer.accepted
                await bench.drain()


@cocotb.test()
async def completed_output_stalls_without_loss_and_replaces_on_same_edge(dut):
    bench = StreamBench(dut, "tx")
    for width in range(1, 9):
        await bench.reset(width, SCRAMBLED)
        first_bits = mapped_bits(0xA5, width, SCRAMBLED)
        next_bits = mapped_bits(0x5A, width, SCRAMBLED)
        # A stalled sink must not prevent collecting a group into empty storage.
        for bit in first_bits:
            transfer = await bench.step(valid=1, data=bit, ready=0)
            assert transfer.accepted
        for _ in range(8):
            transfer = await bench.step(valid=1, data=next_bits[0], ready=0)
            assert not transfer.accepted and not transfer.emitted
        transfer = await bench.step(valid=1, data=next_bits[0], ready=1)
        assert transfer.accepted and transfer.emitted, "TX inserted a replacement bubble"
        for bit in next_bits[1:]:
            await bench.step(valid=1, data=bit)
        await bench.drain()


@cocotb.test()
async def reset_aborts_partial_and_complete_groups(dut):
    bench = StreamBench(dut, "tx")
    for width in range(1, 9):
        for collected in range(1, width + 1):
            await bench.reset(width, SCRAMBLED)
            for _ in range(collected):
                await bench.step(valid=1, data=1, ready=0)
            await bench.reset(width, REVERSED)
            await stream_tx(bench, [0] * width + [1, 0] * width)


@cocotb.test()
async def pause_preserves_partial_and_complete_groups(dut):
    bench = StreamBench(dut, "tx")
    for width in range(1, 9):
        for collected in range(1, width + 1):
            for pause_cycles in (1, 4):
                await bench.reset(width, SCRAMBLED)
                # Prime pads through a real launch so pause checks observe
                # defined pad values, including when a complete group waits.
                await stream_tx(bench, mapped_bits(0x96, width, SCRAMBLED))
                bits = mapped_bits(0xA5, width, SCRAMBLED)
                next_bits = mapped_bits(0x5A, width, SCRAMBLED)
                for bit in bits[:collected]:
                    await bench.step(valid=1, data=bit, ready=0)
                held_input = bits[collected] if collected < width else next_bits[0]
                # TX valid retains group availability during pause. Keep ready
                # high on some paused cycles to verify enable blocks launches
                # without clearing validity or changing the driven pads.
                for cycle in range(pause_cycles):
                    transfer = await bench.step(
                        valid=1, data=held_input, ready=cycle % 2, enabled=0
                    )
                    assert not transfer.accepted and not transfer.emitted
                if collected < width:
                    # Continue at the exact next bit, without restarting the group.
                    for bit in bits[collected:]:
                        transfer = await bench.step(valid=1, data=bit, ready=0)
                        assert transfer.accepted
                else:
                    # A complete group must survive pause and launch alongside
                    # the first accepted bit of the replacement group.
                    transfer = await bench.step(valid=1, data=held_input)
                    assert transfer.accepted and transfer.emitted
                    for bit in next_bits[1:]:
                        await bench.step(valid=1, data=bit)
                await bench.drain()


@cocotb.test()
async def pad_masking_and_hold_between_launches(dut):
    bench = StreamBench(dut, "tx")
    masks = (0x00, 0xFF, 0x55, 0xAA, 0x0F, 0xF0) + tuple(1 << pad for pad in range(8))
    for mapping in (IDENTITY, REVERSED, SCRAMBLED):
        await bench.reset(8, mapping)
        # Establish all pad values through a real launch, not a testbench drive.
        await stream_tx(bench, mapped_bits(0x96, 8, mapping))
        previous = 0x96
        for mask in masks:
            word = previous ^ 0xFF
            dut.uio_oe.value = mask
            for bit in mapped_bits(word, 8, mapping):
                await bench.step(valid=1, data=bit, ready=0)
            # Changing output enables must not change pads without a launch.
            dut.uio_oe.value = mask ^ 0xFF
            await bench.step(ready=0)
            dut.uio_oe.value = mask
            await bench.step(ready=0)
            transfer = await bench.step()
            assert transfer.emitted
            expected = (previous & (~mask & 0xFF)) | (word & mask)
            assert transfer.data == expected, "TX pad update did not respect uio_oe"
            previous = expected
            for ready in (1, 0, 1):
                await bench.step(ready=ready)


@cocotb.test()
async def seeded_random_stalls_and_source_bubbles(dut):
    bench = StreamBench(dut, "tx")
    for width in range(1, 9):
        rng = random.Random(0x545800 + width)
        mapping = list(IDENTITY)
        rng.shuffle(mapping)
        await bench.reset(width, tuple(mapping))
        # Whole groups let the test prove conservation after a bounded drain.
        bits = [rng.randrange(2) for _ in range(80 * width)]
        index = emitted = 0
        presenting = False
        for cycle in range(len(bits) * 8 + 100):
            if index < len(bits) and not presenting and rng.random() < 0.7:
                presenting = True
            ready = cycle % 67 >= 19 and rng.random() < 0.7
            transfer = await bench.step(
                valid=presenting,
                data=bits[index] if index < len(bits) else 0,
                ready=ready,
            )
            if transfer.accepted:
                index += 1
                presenting = False
            emitted += transfer.emitted
            if index == len(bits) and not bench.model.pending:
                break
        else:
            raise AssertionError("random TX stream did not finish before its deadline")
        assert index == len(bits)
        assert emitted == 80, "TX transfer accounting did not balance"
        await bench.step()
