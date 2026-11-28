# Datapath unit tests

These standalone cocotb tests compile only `src/datapath/rx_serializer.sv` or
`src/datapath/tx_parallelizer.sv` and its thin SystemVerilog wrapper. They do
not depend on the unfinished top level, FSM, or FIFO. The source RTL is used
unchanged, and failures are not skipped or marked as expected.

## Setup

Use Icarus Verilog (`iverilog` and `vvp`), Python 3.11+, GNU Make, and GTKWave.
The OSS CAD Suite includes Icarus and GTKWave; add its `bin` directory to
`PATH` if using that distribution. On Debian/Ubuntu, the simulator and viewer
can also be installed with:

```sh
sudo apt-get install iverilog gtkwave python3-venv make
```

From the repository root, install the existing pinned Python requirements:

```sh
python3 -m venv test/datapath/.venv
. test/datapath/.venv/bin/activate
python -m pip install -r test/requirements.txt
```

If your OSS CAD Suite environment already provides `cocotb-config`, you can
use its bundled Python/cocotb instead of creating a virtual environment.

## Run

Run these commands from the repository root:

```sh
# Independent suites:
make -C test/datapath rx
make -C test/datapath tx

# Run both, continuing to TX even if RX fails:
make -k -C test/datapath all
```

Each target checks the cocotb results and returns a nonzero status on a
compile error or failed assertion. The default `make -C test/datapath` runs
both suites, stopping at the first failure. Build products, waveforms, and
`results.xml` files are separate for RX and TX under `test/datapath/sim_build/`.

To run just a timing test (the regular expression matches its Python name):

```sh
make -C test/datapath rx COCOTB_TEST_FILTER=sustained_traffic_has_no_interframe_bubbles
make -C test/datapath tx COCOTB_TEST_FILTER=completed_output_stalls_without_loss_and_replaces_on_same_edge

# Pause/resume retention, separately from reset/abort:
make -C test/datapath rx COCOTB_TEST_FILTER=pause_preserves
make -C test/datapath tx COCOTB_TEST_FILTER=pause_preserves
```

A filtered run overwrites that module's previous waveform and results file.
To remove generated build products:

```sh
make -C test/datapath clean
```

## Generate and view waveforms

Every simulation automatically writes an FST waveform, including failing
simulations that got past compilation. No separate waveform-generation
command or RTL edit is needed. From the repository root:

```sh
make -C test/datapath rx
gtkwave test/datapath/sim_build/rx_serializer/waves.fst test/datapath/rx_serializer.gtkw

# TX writes a waveform even when a behavioral assertion fails:
make -C test/datapath tx
gtkwave test/datapath/sim_build/tx_parallelizer/waves.fst test/datapath/tx_parallelizer.gtkw
```

The saved layouts show clock/reset/enable, width, packed map, data,
ready/valid, and internal buffer/lane signals. Checks only use public ports;
internal signals are included for visual debugging. In `index_map_flat`,
bits `[3*i +: 3]` select the pad for lane `i`. A compilation failure generates
no new waveform or cocotb result file.

## Contract and coverage

`rx_width`/`tx_width` encode **N minus one**, for N=1 through 8. Configuration
stays constant during a frame and changes only during reset in these tests.
Inputs settle for 10 ns before each rising edge and outputs are checked
before the edge and 10 ns after it, giving a 20 ns clock period (50 MHz).
These are functional cycle-timing checks; they do not measure physical
setup/hold margins or post-layout timing.

Transfers happen on rising edges with `enable && valid && ready` high. A
producer holds its valid data while blocked; invalid input data may change.
RX must retain valid output data during downstream stalls; TX must retain
its completed staged group and leave the registered pads unchanged.
An empty buffer may collect input while the sink is stalled. A low enable
pauses the module: input ready goes low, and buffered data, progress, and
pad values are retained through disabled clock edges. RX output valid is
gated low by its enable. TX output valid reports stored group availability
and retains its value during pause; it must not be counted as a launch
unless `tx_en && tx_out_stream_valid && tx_out_stream_ready` is true.
The downstream consumer must use that same launch acceptance condition.
Re-enabling resumes at the exact next bit, including a completed group
waiting to launch. Source valid and sink ready may remain high during a
pause without causing transfers. Configuration stays unchanged while paused.
Active-low reset separately discards stream state asynchronously. TX's pad
register has no specified reset value and is not required to reset to zero.

RX stores one accepted pad snapshot, then emits `snapshot[index_map[i]]`
for i=0 through N-1. The last bit may be consumed on the same edge as the
next snapshot is accepted. With a continuous source and ready sink, the
first output transfer occurs one clock after the first snapshot transfer,
then one bit transfers every clock with no gap between frames.

TX collects N **accepted** input bits, placing bit i on `index_map[i]`.
Ready remains high while a group is incomplete. Output valid asserts only
after the Nth accepted bit, and a completed group remains stable until
consumed. Consuming a group and accepting the next group's first bit may
happen on the same edge. With continuous traffic, input transfers every
clock and output transfers every N clocks, including every clock for N=1.
`uio_out` is the TX data output; the former `tx_out_stream` port is no longer
used. TX pads are registered, so the bench samples the launched group
**after** the edge with `tx_en && tx_out_stream_valid && tx_out_stream_ready`. When
valid first asserts, the pads still hold the previous launch. The bench
checks the launched group even if a new group starts on the same edge.

`uio_oe` is sampled on the launch edge: enabled mapped pads take their new
bits, and disabled pads retain their previous values. Pads must otherwise
hold through idle cycles, downstream stalls, and disable. Unknown startup
values on pads not yet written are allowed; previously known pad values
must remain defined. Values written to enabled, unmapped pads are not
specified. RX allows repeated map entries; TX tests use permutations to
avoid ambiguous writes to the same pad. Checks use only public ports.

RX includes eight tests; TX includes nine:

| Coverage | Checks |
| --- | --- |
| Reset, idle, disable | Asynchronous stream-state clear and RX data clear, idle valid low, disabled interfaces, restart |
| Exhaustive data and maps | All widths, all 256 pad patterns, identity/reversed/scrambled maps; RX also tests repeated selections |
| Continuous traffic | Exact transfer cycles, one-bit throughput, consecutive frames, simultaneous dequeue/enqueue |
| Downstream backpressure | Stable stalled data/valid, no lost data or overwrite, immediate recovery; RX stalls every lane |
| Source gaps | RX snapshot isolation from changing live pads; TX gaps before every lane, including the last |
| Reset aborts | Reset at every RX lane and every TX partial/complete group, fresh frame starts at lane zero |
| Pause/resume | One- and four-cycle pauses at every RX lane and every TX partial/complete group, no transfers while paused, exact continuation, preserved TX pads |
| TX registered pads | Data checked after launch, output-enable masks, disabled-pad retention, pad stability between launches |
| Seeded random traffic | Legal producer behavior, source bubbles, short and long sink stalls, per-cycle scoreboard, transfer accounting |

The reference models track transactions (a queue of RX bits, or collected
TX bits and a completed group), rather than reproducing the DUT's internal
`busy`, `load`, or lane-counter logic. Continuous-traffic tests also assert
the complete list of expected transfer cycles, so inserting a bubble cannot
pass merely because data eventually arrives.

## RTL concerns

Current validation: RX passes 8/8 tests and TX passes 9/9 using the installed
OSS CAD Suite (Icarus 14.0 development build, cocotb 2.1.0 development build).

TX retains output valid as a group-availability flag during pause. This is
intentional, and the scoreboard qualifies actual transfers with enable.
Pause tests exercise high source valid and toggling sink ready while
disabled, check that pads and staged data remain intact, and verify correct
continuation on resume. Reset is still checked separately as an abort.

RX's snapshot buffer, `busy` flag, and last-bit replacement logic otherwise
fit serialization. RX need not mirror TX's assembly control: RX drains a
captured word while TX collects a word. Both should share enable-as-pause
and reset-as-abort behavior. No source RTL was changed by this test update.
