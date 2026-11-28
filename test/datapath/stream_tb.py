"""Cycle-level ready/valid checks against independent transaction models.

Inputs change with the clock low. Outputs are checked before the sampling
edge and again after registered/combinational updates have settled. No DUT
internals are read. The clock period is 20 ns, matching info.yaml's 50 MHz.
"""

from collections import deque
from dataclasses import dataclass

from cocotb.triggers import Timer


IDENTITY = tuple(range(8))
REVERSED = tuple(reversed(IDENTITY))
SCRAMBLED = (3, 0, 7, 2, 5, 1, 6, 4)
REPEATED = (7, 7, 0, 0, 5, 5, 2, 2)


def mapped_bits(word, width, mapping):
    return [(word >> pad) & 1 for pad in mapping[:width]]


class RxReference:
    """One pad snapshot, represented only as the bits left to emit."""

    def __init__(self, width, mapping):
        self.width = width
        self.mapping = mapping
        self.bits = deque()

    def outputs(self, enabled, ready):
        in_ready = enabled and (not self.bits or (len(self.bits) == 1 and ready))
        valid = enabled and bool(self.bits)
        return bool(in_ready), bool(valid), self.bits[0] if valid else 0

    def advance(self, enabled, accepted, emitted, data):
        if not enabled:
            return
        if emitted:
            self.bits.popleft()
        if accepted:
            assert not self.bits, "reference exceeded one snapshot of storage"
            self.bits.extend(mapped_bits(data, self.width, self.mapping))

    @property
    def pending(self):
        return bool(self.bits)


class TxReference:
    """Collect N bits; retain group availability through stalls and pause."""

    def __init__(self, width, mapping):
        self.width = width
        self.mapping = mapping
        self.bits = []
        self.word = None
        self.mask = sum(1 << pad for pad in mapping[:width])

    def outputs(self, enabled, ready):
        in_ready = enabled and (self.word is None or ready)
        # TX valid reports stored group availability even while paused.
        # Launch acceptance is separately qualified by enable.
        valid = self.word is not None
        return bool(in_ready), bool(valid), self.word if valid else 0

    def advance(self, enabled, accepted, emitted, data):
        if not enabled:
            return
        if emitted:
            self.word = None
        if accepted:
            assert self.word is None, "reference overwrote a stalled output"
            self.bits.append(data)
            if len(self.bits) == self.width:
                self.word = sum(bit << pad for bit, pad in zip(self.bits, self.mapping))
                self.bits.clear()

    @property
    def pending(self):
        return self.word is not None or bool(self.bits)


@dataclass(frozen=True)
class Transfer:
    cycle: int
    accepted: bool
    emitted: bool
    data: int


class StreamBench:
    def __init__(self, dut, direction):
        self.dut = dut
        self.direction = direction
        self.en = getattr(dut, f"{direction}_en")
        self.width_signal = getattr(dut, f"{direction}_width")
        self.in_valid = getattr(dut, f"{direction}_in_stream_valid")
        self.in_ready = getattr(dut, f"{direction}_in_stream_ready")
        self.out_valid = getattr(dut, f"{direction}_out_stream_valid")
        self.out_ready = getattr(dut, f"{direction}_out_stream_ready")
        self.out_data = dut.rx_out_stream if direction == "rx" else dut.uio_out
        self.in_data = dut.uio_in if direction == "rx" else dut.tx_in_stream
        self.cycle = 0
        self.pad_value = 0
        self.pad_known_mask = 0

    def read_pads(self):
        """Read known pad bits without converting unknown startup bits to int."""
        value = known_mask = 0
        for bit, state in enumerate(reversed(str(self.out_data.value))):
            if state in "01":
                known_mask |= 1 << bit
                value |= int(state) << bit
        return value, known_mask

    def check_pads(self, context):
        actual_value, actual_known_mask = self.read_pads()
        assert actual_known_mask & self.pad_known_mask == self.pad_known_mask, (
            f"{context}: uio_out={self.out_data.value} has unknown bits on "
            f"previously defined pads, mask=0x{self.pad_known_mask:02x}"
        )
        assert actual_value & self.pad_known_mask == self.pad_value & self.pad_known_mask, (
            f"{context}: uio_out=0x{actual_value:02x}, "
            f"expected 0x{self.pad_value:02x}, mask=0x{self.pad_known_mask:02x}; "
            "pads must update on a valid/ready launch and otherwise hold"
        )

    def check(self, enabled, ready, phase):
        expected_ready, expected_valid, expected_data = self.model.outputs(enabled, ready)
        context = (
            f"{self.direction} width={self.width} map={self.mapping} "
            f"cycle={self.cycle} {phase}"
        )
        actual_ready = int(self.in_ready.value)
        actual_valid = int(self.out_valid.value)
        assert actual_ready == expected_ready, (
            f"{context}: input ready={actual_ready}, expected {int(expected_ready)}"
        )
        assert actual_valid == expected_valid, (
            f"{context}: output valid={actual_valid}, expected {int(expected_valid)}"
        )
        if self.direction == "tx":
            # A complete group is staged internally. Public pads update only
            # AFTER its valid/ready edge, not when output valid first asserts.
            self.check_pads(context)
        elif expected_valid:
            actual_data = int(self.out_data.value)
            assert actual_data == expected_data, (
                f"{context}: output=0x{actual_data:02x}, "
                f"expected 0x{expected_data:02x}"
            )

    async def reset(self, width=8, mapping=IDENTITY):
        assert 1 <= width <= 8
        assert len(mapping) == 8 and all(0 <= pad < 8 for pad in mapping)
        if self.direction == "tx":
            assert len(set(mapping)) == 8, "TX mapping must not alias output pads"
        self.width = width
        self.mapping = mapping
        model_type = RxReference if self.direction == "rx" else TxReference
        self.model = model_type(width, mapping)
        self.cycle = 0

        self.dut.clk.value = 0
        self.dut.rst_n.value = 1
        self.en.value = 1
        self.in_valid.value = 0
        self.out_ready.value = 0
        self.in_data.value = 0
        if self.direction == "tx":
            self.dut.uio_oe.value = 0xFF
        await Timer(2, unit="ns")
        self.dut.rst_n.value = 0
        self.width_signal.value = width - 1
        self.dut.index_map_flat.value = sum(pad << (3 * lane) for lane, pad in enumerate(mapping))
        # There is deliberately no rising edge during this reset pulse.
        await Timer(2, unit="ns")
        if self.direction == "tx":
            # There is no specified reset value for the registered pad output.
            # Seed known bits from the public port, without driving the DUT.
            self.pad_value, self.pad_known_mask = self.read_pads()
        self.check(True, False, "asynchronous reset, before any clock")
        if self.direction == "rx":
            assert int(self.out_data.value) == 0, "reset must clear the data buffer"
        self.dut.rst_n.value = 1
        await Timer(2, unit="ns")
        self.check(True, False, "reset released")

    async def step(self, *, valid=0, data=0, ready=1, enabled=1):
        self.dut.clk.value = 0
        self.en.value = enabled
        self.in_valid.value = valid
        self.out_ready.value = ready
        self.in_data.value = data
        await Timer(10, unit="ns")
        self.check(bool(enabled), bool(ready), "before rising edge")
        accepted = bool(enabled and valid and int(self.in_ready.value))
        emitted = bool(enabled and ready and int(self.out_valid.value))
        output = int(self.out_data.value) if emitted and self.direction == "rx" else 0
        if emitted and self.direction == "tx":
            # Predict the pad register from the group being launched, before
            # advancing the model to a possibly simultaneous new input bit.
            oe = int(self.dut.uio_oe.value)
            written_mask = oe & self.model.mask
            self.pad_value = (self.pad_value & ~oe) | (self.model.word & written_mask)
            # Enabled, unmapped pads have no specified data. Disabled pads
            # retain any known previous value, including across later groups.
            self.pad_known_mask = (self.pad_known_mask & ~oe) | written_mask
        self.dut.clk.value = 1
        self.model.advance(bool(enabled), accepted, emitted, data)
        await Timer(10, unit="ns")
        self.check(bool(enabled), bool(ready), "after rising edge")
        if emitted and self.direction == "tx":
            output, _ = self.read_pads()
        transfer = Transfer(self.cycle, accepted, emitted, output)
        self.cycle += 1
        return transfer

    async def drain(self):
        # A TX partial group must be completed by its producer before draining.
        for _ in range(self.width + 2):
            if not self.model.pending:
                await self.step()
                return
            await self.step()
        raise AssertionError("stream did not drain within the bounded deadline")


async def stream_rx(bench, words):
    """Continuous legal producer/sink; also enforce exact transfer cycles."""
    words = list(words)
    accepted_cycles, emitted_cycles, outputs = [], [], []
    index = 0
    for _ in range(len(words) * bench.width + 2):
        transfer = await bench.step(
            valid=index < len(words), data=words[index] if index < len(words) else 0
        )
        if transfer.accepted:
            accepted_cycles.append(transfer.cycle)
            index += 1
        if transfer.emitted:
            emitted_cycles.append(transfer.cycle)
            outputs.append(transfer.data)
        if index == len(words) and not bench.model.pending:
            break
    expected = [bit for word in words for bit in mapped_bits(word, bench.width, bench.mapping)]
    assert outputs == expected, "RX lost, duplicated, reordered, or corrupted bits"
    start = accepted_cycles[0]
    assert accepted_cycles == list(range(start, start + len(expected), bench.width))
    assert emitted_cycles == list(range(start + 1, start + len(expected) + 1)), (
        "RX inserted a bubble"
    )
    await bench.step()


async def stream_tx(bench, bits):
    """One bit accepted per clock; a complete group emitted every N clocks."""
    bits = list(bits)
    assert bits and len(bits) % bench.width == 0
    accepted_cycles, emitted_cycles, outputs = [], [], []
    index = 0
    for _ in range(len(bits) + 2):
        transfer = await bench.step(
            valid=index < len(bits), data=bits[index] if index < len(bits) else 0
        )
        if transfer.accepted:
            accepted_cycles.append(transfer.cycle)
            index += 1
        if transfer.emitted:
            emitted_cycles.append(transfer.cycle)
            outputs.append(transfer.data & bench.model.mask)
        if index == len(bits) and not bench.model.pending:
            break
    expected = [
        sum(bit << pad for bit, pad in zip(bits[start:start + bench.width], bench.mapping))
        for start in range(0, len(bits), bench.width)
    ]
    assert outputs == expected, "TX lost, duplicated, reordered, or corrupted bits"
    start = accepted_cycles[0]
    assert accepted_cycles == list(range(start, start + len(bits))), "TX stalled while collecting"
    assert emitted_cycles == list(range(start + bench.width, start + len(bits) + 1, bench.width)), (
        "TX inserted a bubble or reported a group before its last bit was accepted"
    )
    await bench.step()
