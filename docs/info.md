<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

The current top connects an RV32EC Ibex core to independent 4 KiB instruction
and 2 KiB data SRAM banks through a one-cycle adapter. Code goes in instruction
SRAM; constants, globals, stack, and buffers go in data SRAM. See
[SRAM integration](sram.md) for the address map, handshake behavior, and tests.
The external program loader and physical SRAM placement/power configuration
remain to be implemented; the simulation testbench preloads its test program.

## How to test

### Ibex standalone hello-world simulation

This checks the upstream Ibex Simple System simulator and RISC-V software
toolchain. It runs separately from the Tiny Tapeout wrapper and cocotb tests.

The local setup uses `.venv-ibex` with FuseSoC 2.4.3, its dependencies, and
`packaging`; Verilator from OSS CAD Suite; and Homebrew's `libelf`, `lz4`, and
`riscv64-elf-gcc`. These tools must already be installed. The commands below
restore the environment in each new terminal without reinstalling anything.

Start in the repository root (`js_protocol_emulator_asic/`):

```bash
source .venv-ibex/bin/activate

# Both ELF include directories are needed by Homebrew's header layout.
export CPATH="$(brew --prefix libelf)/include:$(brew --prefix libelf)/include/libelf:$(brew --prefix lz4)/include${CPATH:+:$CPATH}"
export LIBRARY_PATH="$(brew --prefix libelf)/lib:$(brew --prefix lz4)/lib${LIBRARY_PATH:+:$LIBRARY_PATH}"

cd src/vendor/ibex
```

Build the hardware simulator:

```bash
fusesoc --cores-root=. run --target=sim --setup --build \
  lowrisc:ibex:ibex_simple_system \
  --verilator_options=-Wno-UNOPTFLAT
```

`--setup --build` only creates the simulator executable; it does not execute a
test. Entering and leaving the build directory can mean the build completed
without needing further compilation. The Edalize backend deprecation warning
does not indicate a test failure. The `UNOPTFLAT` option suppresses that Verilator
warning category for this standalone simulation.

Still in `src/vendor/ibex`, compile the hello-world program and run it:

```bash
# Build only the ELF, so srecord is not required.
make -C examples/sw/simple_system/hello_test hello_test.elf \
  CC=riscv64-elf-gcc ARCH=rv32imc_zicsr_zifencei

./build/lowrisc_ibex_ibex_simple_system_0/sim-verilator/Vibex_simple_system \
  --term-after-cycles=1000000 \
  --meminit=ram,examples/sw/simple_system/hello_test/hello_test.elf

cat ibex_simple_system.log
```

The simulator should print `Terminating simulation by software request.` and
simulation statistics. The cycle limit prevents a stalled program from running
indefinitely; reaching that limit is not a successful completion.

The program's text is written to `ibex_simple_system.log` in the current
directory. A successful run produces:

```text
Hello simple system
DEADBEEF
BAADF00D
Tick!
Tock!
Tick!
Tock!
Tick!
```

After running the simulator, check the greeting automatically with:

```bash
grep -Fxq 'Hello simple system' ibex_simple_system.log \
  && echo 'PASS: Ibex hello-world greeting found'
```

This greeting check is a smoke check, not a full CPU verification suite. The run
also creates `ibex_simple_system_pcount.csv` (performance counters) and
`trace_core_00000000.log` (instruction trace). Add `-t` to the simulator command
to record a waveform. Re-running the simulator replaces its output logs.

## External hardware

List external hardware used in your project (e.g. PMOD, LED display, etc), if any
