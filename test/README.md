# UART testbenches

Cocotb is Python code running alongside an HDL simulator. The simulator executes
the SystemVerilog; Python drives inputs, waits for simulated events, and checks
outputs. These benches use [Cocotb](https://docs.cocotb.org/en/stable/).

## How the existing test works

- `tb.v` instantiates one UART and exposes its ports to Python as `dut`.
- `@cocotb.test()` registers an `async def` function as a test.
- `Clock(...).start()` generates the clock in a background coroutine.
- `signal.value = ...` drives a signal; `int(signal.value)` reads it.
- `await ClockCycles(...)` waits for clock edges; `await Timer(...)` waits for
  simulation time. An `await` lets the simulator and other coroutines advance.
- `tick()` waits for an edge and then 1 ns so the HDL's `<=` updates have settled.
- `transmit()` offers a parallel byte and checks the outgoing serial frame.
  In `for expected_bit in frame`, the outer loop visits start, eight data bits,
  and stop. The inner loop checks that bit throughout its 104 system clocks.
- `receive()` acts as an independent external serial transmitter. `take()`
  accepts a queued parallel byte by asserting RX_READY for one rising edge.
- `cocotb.start_soon(...)` runs an operation concurrently; ordinary `await helper()`
  waits for that helper to finish before continuing.
- An `assert` mismatch fails the test. Timeout limits catch missing handshakes.

## Two-UART learning scaffold

The additional files are independent of the existing single-UART tests:

- `tb_dual.sv`: two UART instances on a shared clock/reset, with A.TX connected
  to B.RX and B.TX connected to A.RX. Named parallel signals hide the pin masks.
- `test_dual.py`: reset, bounded handshake helpers, and one byte sent each way.
  The TODOs are exercises for you to implement.
- `Makefile.dual`: a separate RTL-only simulator build and results file.

Run from this directory:

```sh
make -f Makefile.dual
```

The waveform is `tb_dual.fst`; results are in `results_dual.xml`.
Open the provided signal selection with `gtkwave tb_dual.fst dual.gtkw`.
It groups A's parallel input, the A-to-B serial connection, B's receive shift
register, and B's FIFO/parallel handshake. B's `rx_data` is valid only while
`b_rx_valid` is high: after the last queued byte is popped, the output becomes
zero. In `one_byte_each_way`, zoom near 1002–1003 us to see B enqueue and consume
the first `0xA5`; a one-clock-wide parallel byte is hard to see at frame scale.
In this bench, Python drives only the parallel interfaces. The actual DUTs
generate and decode the serial frames:

```text
Python -> A parallel TX -> A UART TX -> B UART RX -> B FIFO -> Python
Python <- A FIFO <- A UART RX <- B UART TX <- B parallel TX <- Python
```

Start with a sequence in one direction, then test simultaneous traffic. Keep
RX_READY low while waiting for RX_VALID so the FIFO retains the byte you want
to inspect. Read the data before the rising edge that accepts it. Waiting on
RX_VALID with RX_READY already high can allow the byte to be consumed before
your test checks it.

Keep the original single-UART tests too: two identical UARTs can share a timing
or bit-order mistake and still communicate with each other successfully.

## How to run

To run the RTL simulation:

```sh
make -B
```

To run gatelevel simulation, first harden your project and copy `../runs/wokwi/results/final/verilog/gl/{your_module_name}.v` to `gate_level_netlist.v`.

Then run:

```sh
make -B GATES=yes
```

If you wish to save the waveform in VCD format instead of FST format, edit tb.v to use `$dumpfile("tb.vcd");` and then run:

```sh
make -B FST=
```

This will generate `tb.vcd` instead of `tb.fst`.

## How to view the waveform file

Using GTKWave

```sh
gtkwave tb.fst tb.gtkw
```

Using Surfer

```sh
surfer tb.fst
```
