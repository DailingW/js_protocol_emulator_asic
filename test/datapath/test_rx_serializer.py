"""RX snapshot, mapping, flow control, and cycle-exact throughput tests."""

import random

import cocotb

from stream_tb import IDENTITY, REPEATED, REVERSED, SCRAMBLED, StreamBench, mapped_bits, stream_rx


@cocotb.test()
async def reset_idle_and_disable(dut):
    bench = StreamBench(dut, "rx")
    for width in range(1, 9):
        await bench.reset(width)
        # An empty buffer must accept a snapshot even with the sink stalled.
        for ready in (0, 1, 0):
            await bench.step(ready=ready)
        for _ in range(3):
            transfer = await bench.step(valid=1, data=0xFF, enabled=0)
            assert not transfer.accepted and not transfer.emitted
        await stream_rx(bench, [0x96, 0x69])


@cocotb.test()
async def exhaustive_widths_pad_patterns_and_maps(dut):
    bench = StreamBench(dut, "rx")
    # Includes non-power-of-two widths and duplicate input-pad selections.
    for width in range(1, 9):
        for mapping in (IDENTITY, REVERSED, SCRAMBLED, REPEATED):
            await bench.reset(width, mapping)
            await stream_rx(bench, range(256))


@cocotb.test()
async def sustained_traffic_has_no_interframe_bubbles(dut):
    bench = StreamBench(dut, "rx")
    for width in range(1, 9):
        await bench.reset(width, SCRAMBLED)
        # stream_rx checks every handshake cycle, including width=1 and
        # simultaneous last-bit dequeue / next-snapshot enqueue.
        await stream_rx(bench, [0xA5, 0x5A, 0x00, 0xFF] * 16)


@cocotb.test()
async def backpressure_on_every_lane_and_frame_boundary(dut):
    bench = StreamBench(dut, "rx")
    for width in range(1, 9):
        for stalled_lane in range(width):
            await bench.reset(width, REVERSED)
            first = await bench.step(valid=1, data=0xA5, ready=0)
            assert first.accepted
            for _ in range(stalled_lane):
                await bench.step(valid=1, data=0x5A)
            # The next snapshot remains stable while waiting for capacity.
            for _ in range(5):
                transfer = await bench.step(valid=1, data=0x5A, ready=0)
                assert not transfer.accepted and not transfer.emitted
            for lane in range(stalled_lane, width):
                transfer = await bench.step(valid=1, data=0x5A)
                assert transfer.emitted
                assert transfer.accepted == (lane == width - 1)
            await bench.drain()


@cocotb.test()
async def snapshot_is_independent_of_live_pads_and_source_gaps(dut):
    bench = StreamBench(dut, "rx")
    for width in range(1, 9):
        await bench.reset(width, SCRAMBLED)
        for word in (0xD2, 0x2D, 0x81, 0x7E):
            await bench.step(valid=1, data=word, ready=0)
            # With valid=0 the producer may change pads every cycle. The
            # buffered snapshot and stalled output must remain unchanged.
            for noise in (0xFF, 0x00, 0xA5):
                await bench.step(data=noise, ready=0)
            for lane in range(width):
                await bench.step(data=(word ^ (0xFF >> lane)))
            for ready in (1, 0, 1):
                await bench.step(data=word ^ 0xFF, ready=ready)
            assert not bench.model.pending


@cocotb.test()
async def reset_aborts_every_partial_snapshot(dut):
    bench = StreamBench(dut, "rx")
    for width in range(1, 9):
        for consumed in range(width):
            await bench.reset(width, SCRAMBLED)
            await bench.step(valid=1, data=0xFF)
            for _ in range(consumed):
                await bench.step()
            await bench.step(ready=0)
            # Reset must flush a valid stalled output without a clock.
            await bench.reset(width, REVERSED)
            await stream_rx(bench, [0x00, 0x96, 0x69])


@cocotb.test()
async def pause_preserves_every_remaining_snapshot_lane(dut):
    bench = StreamBench(dut, "rx")
    for width in range(1, 9):
        for consumed in range(width):
            for pause_cycles in (1, 4):
                await bench.reset(width, SCRAMBLED)
                await bench.step(valid=1, data=0xA5, ready=0)
                for _ in range(consumed):
                    await bench.step()
                held_bit = str(dut.rx_out_stream.value)
                # A pending next snapshot stays stable until it is accepted.
                # Toggling sink ready during pause must not consume old bits.
                for cycle in range(pause_cycles):
                    transfer = await bench.step(
                        valid=1, data=0x3C, ready=cycle % 2, enabled=0
                    )
                    assert not transfer.accepted and not transfer.emitted
                    assert str(dut.rx_out_stream.value) == held_bit, "paused RX lane changed"
                # Resume with the sink still stalled: original data must reappear.
                await bench.step(valid=1, data=0x3C, ready=0)
                resumed_bits = []
                for _ in range(width + 1):
                    transfer = await bench.step(valid=1, data=0x3C)
                    if transfer.emitted:
                        resumed_bits.append(transfer.data)
                    if transfer.accepted:
                        break
                else:
                    raise AssertionError("RX did not resume accepting snapshots")
                assert resumed_bits == mapped_bits(0xA5, width, SCRAMBLED)[consumed:]
                await bench.drain()


@cocotb.test()
async def seeded_random_stalls_and_source_bubbles(dut):
    bench = StreamBench(dut, "rx")
    for width in range(1, 9):
        rng = random.Random(0x525800 + width)
        mapping = tuple(rng.randrange(8) for _ in range(8))
        await bench.reset(width, mapping)
        pending = None
        accepted = emitted = 0
        for cycle in range(900):
            if pending is None and rng.random() < 0.75:
                pending = rng.randrange(256)
            # Force long stalls in addition to independent random readiness.
            ready = cycle % 71 >= 17 and rng.random() < 0.7
            transfer = await bench.step(
                valid=pending is not None,
                data=pending if pending is not None else rng.randrange(256),
                ready=ready,
            )
            if transfer.accepted:
                accepted += 1
                pending = None
            emitted += transfer.emitted
        if pending is not None:
            for _ in range(width + 1):
                transfer = await bench.step(valid=1, data=pending)
                emitted += transfer.emitted
                if transfer.accepted:
                    accepted += 1
                    break
            else:
                raise AssertionError("RX producer remained blocked after the sink resumed")
        while bench.model.pending:
            transfer = await bench.step()
            emitted += transfer.emitted
        assert accepted > 10
        assert emitted == accepted * width, "RX transfer accounting did not balance"
        await bench.step()
