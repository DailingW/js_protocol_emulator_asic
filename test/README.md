# SRAM and CPU tests

Use the existing OSS CAD Suite with cocotb. No separate Python environment is
needed. Run the following from `test/`:

```sh
make -f Makefile.sram
make -f Makefile.sram SRAM_TEST=logic
make
```

The first command tests the two raw SRAM banks. The second tests the memory
adapter against the real SRAM models, including simultaneous requests, byte
writes, invalid-address handling, and reset/enable timing. Both use Icarus Verilog.

The normal `make` target tests the complete Ibex + SRAM system using Verilator
5.036 or newer and a C++ compiler. It replaces the original sample adder test.
Generated Ibex sources are prepared automatically. The testbench preloads the
checked-in `programs/sram_smoke.hex`, so a software compiler is not needed to run
it. The program performs word/byte/halfword memory operations and ends in `WFI`.
The test checks CPU transactions through the top-level observation pins.

`Makefile.sram` is an alternative Makefile for isolated memory tests;
`sram_models.mk` shares the SRAM simulation sources and defines between both
Makefiles. See [SRAM integration](../docs/sram.md) for the address map, signal
roles, and current top-level pin behavior.

For Verilator waveform output, run:

```sh
make VERILATOR_TRACE=1
```

Gate-level simulation still needs a hardware loader to initialize program SRAM.
The RTL testbench's direct model preload is not available in a synthesized
netlist. Physical macro views, placement, and power-grid configuration are now
set up; see [SRAM PDN setup and checks](../src/sram/README.md) for the local
hardening commands and the checks still needed after routing.
