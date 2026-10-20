# RV32EC area reference

This document records the earlier area-reference harness. The current TT top
has since been connected to instruction/data SRAM through `sram_logic`; see
[SRAM integration](sram.md) for current wiring, pin behavior, and tests.

`src/tt_um_protocolemu_dailingw.sv` now instantiates `ibex_area_core`, which
instantiates upstream `ibex_top`. Change the explicit parameters in
`src/ibex_area_core.sv` to change the synthesized configuration. FuseSoC and
`ibex_configs.yaml` are not involved in the Tiny Tapeout build.

The baseline has 16 integer registers, basic compressed instructions, a flip-flop
register file, a two-stage pipeline, and no M/B extensions, PMP, instruction cache,
security hardening, branch predictor, or additional performance-event counters.
Baseline cycle/instruction counters and debug-mode logic still exist; disabling
debug triggers is not the same as removing all debug logic.

## Why the CPU survives synthesis

Both instruction data and load data are independent 32-bit words, loaded a byte
at a time from the inputs. All instruction-address, data-address, and write-data
bits are observable through the output-byte selector. Handshakes are also driven
from inputs. This permits arbitrary instructions and data, rather than supplying
a fixed instruction such as a NOP that could specialize away most of the core.

There are no blanket `keep` or `dont_touch` constraints. Unused configured-out
features can be removed normally. A dangling `_unused` reduction would not
retain circuitry. The initial local synthesis check confirmed that all 15
writable registers retained 32 bits each, connected to actual flip-flops.

## GDS build

`info.yaml` lists the required RTL. `src/config.json` enables LibreLane's Slang
frontend and the required include directories. The GDS workflow prepares the
generated source automatically. Existing tile allocation and clock target are
unchanged; fit and timing still require the IHP hardening run.

Push the project and use the existing GDS workflow; no local synthesis command
is required. Library-mapped synthesis statistics are in
`tt_submission/stats/synthesis-stats.txt` and the Yosys synthesis step's
`reports/stat.rpt` in the build artifacts. The result includes the 64 response-word
flip-flops and the loading/observation logic. It excludes program ROM and data RAM.
When comparing configurations, use the same library, synthesis settings, and top.

The source list in `info.yaml` covers this configuration. Enabling features such
as cache, multiplication, PMP, or security also requires their RTL/primitive
dependencies in that list.

`src/ibex_lint.vlt` is passed only to Verilator using `LINTER_VLT`. It waives
intentional open outputs, unused vendor configuration constants, the disabled
multiplier/divider's unused signals, and specific upstream
decode/control scheduling warnings. These waivers change no RTL or synthesis
behavior. Checks remain enabled for the TT top and for other warning types,
including missing pins, width mismatches, inferred latches, and multiple drivers.
Review the waivers when changing the core configuration or upstream revision.

The upstream `ibex_top.sv` contains a nonconstant declaration initializer on the
unused signal `unused_scramble_inputs`. Slang rejects that initialization.
`scripts/prepare_ibex.py` changes that one declaration from `logic` to `wire` in
an ignored generated copy at `src/generated/ibex_top.sv`. This makes it a
continuous unused-input expression and leaves the submodule untouched. Do not
compile both the original and generated `ibex_top`.

The preparation step also generates `src/generated/ibex_ex_block.sv`, adding
explicit zero tie-offs to the absent multiplier/divider's outputs under
`RV32MNone`. This fixes the 66 undriven-bit diagnostics in LibreLane's early
Yosys check. The affected paths are unselected and disappear during optimization,
but the flow counts the early diagnostics even when the final netlist checks
cleanly. Synthesis checks remain enabled. Compile the generated execute block
instead of the original; the submodule remains unchanged.

After a fresh checkout, run `python3 scripts/prepare_ibex.py` before local tools
read `info.yaml`. The GDS workflow already does this automatically.

The existing cocotb Makefile and adder test have not been adapted for this core.
Before using RTL simulation or the workflow's separate gate-level test job, add
the required simulator/source setup and replace the adder assertion with CPU or
peripheral tests. This does not affect the GDS synthesis job.

## Pin harness

`ena` allows instruction fetching and byte writes. With `uio_in[3] = 1`, a rising
clock loads `ui_in` into the response byte selected by `uio_in[2:0]`: indices
0–3 select instruction bytes from least to most significant; 4–7 select load-data
bytes. With `uio_in[3] = 0`, the `ui_in` bits instead supply:

| Bit | Core input |
| --- | --- |
| 0 | Instruction grant |
| 1 | Instruction response valid |
| 2 | Data grant |
| 3 | Data response valid |
| 4 | Instruction response error |
| 5 | Data response error |
| 6 | External interrupt |
| 7 | Debug request |

`uio_in[7:4]` selects the byte on `uo_out`: 0–3 instruction address, 4–7 data
address, 8–11 store data, all least-significant byte first. Selection 12 returns
`{core_sleep, data_be[3:0], data_we, data_req, instr_req}`; selection 13 returns
fault/alert status. Other selections return zero. All bidirectional pins are
inputs. Interrupts other than the external interrupt are tied low.

This harness is for synthesis characterization. It contains no memory, firmware,
or bus-response controller. The reset PC is 0x00000080; any future driver must
obey Ibex's memory-interface protocol.
