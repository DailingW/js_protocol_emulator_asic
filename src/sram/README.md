# FSM state SRAM

Integration follows the [IHP SRAM guide](https://kdp1965.github.io/ihp-um-janestreet-prism/ihp_sram_macro.html).
The physical dimensions, supplies, and port widths were checked against
IHP-Open-PDK commit `2bbec755dc67ca3db0261c3d6163e15735d66710`, under
`ihp-sg13cmos5l/libs.ref/sg13cmos5l_sram/`.

## RTL and interface

Each `fsm_main` contains `sram_logic u_state_mem`, which contains
`sram_banks u_banks` and two `RM_IHPSG13_1P_64x64_c2_bm_bist` instances:

| Path relative to `fsm_main` | State word bits |
| --- | --- |
| `u_state_mem.u_banks.u_lo` | `[63:0]` |
| `u_state_mem.u_banks.u_hi` | `[127:64]` |

Together they store 64 state words of 128 bits (1024 bytes). Duplicating
`fsm_main` duplicates the memories; there is no shared global bank.
`sram.sv` declares the synthesis black box. Simulations use the vendored PDK
models in `test/ihp_sram/`, with both `SIM` and `FUNCTIONAL` defined.

The provisional memory interface on `fsm_main` is:

| Port | Meaning |
| --- | --- |
| `state_mem_en` | Accept an operation on the next rising edge when `rst_n` is high. |
| `state_mem_we` | 0 reads; 1 writes. There is one shared address/operation port. |
| `state_mem_addr[5:0]` | State word index, 0 through 63 (not a byte address). |
| `state_mem_wdata[127:0]` | Write data, low/high halves sent to the matching macros. |
| `state_mem_wmask[127:0]` | Per-bit mask: 1 writes that bit; 0 preserves it. |
| `state_word[127:0]` | SRAM read output; this replaces the previous external input. |
| `state_word_valid` | High after an accepted read edge; low after writes/idle or during reset. |

Read output changes after the accepting rising edge, without an extra wrapper
pipeline stage. Writes do not enable write-through and hold the previous read
output. Reset inhibits both macros and clears only the valid flag; neither
contents nor data output have a reset value. Program each word before reading
it. Read output may retain a value while valid is low.

The memory controls remain explicit until the fetch controller and loader are
designed. They are not connected to the unfinished `state` output or gated by
`rx_en`/`tx_en`. The existing pad-edge logic and unfinished FSM logic are
unchanged. The future controller must handle the synchronous fetch latency and
arbitrate programming versus fetches, since these are single-port memories.

Both macros tie `A_DLY` high and every BIST input low. The mask stays per-bit;
there is no CPU address decoder, Ibex handshake, or byte-enable expansion.

## Physical setup

Each macro is **784.48 x 64.36 micrometres**, from its LEF and datasheet.
The provisional placement in `src/config.json` stacks them with their Metal2
signal pins facing a 64.16 micrometre gap:

| Instance suffix | Lower-left position | Orientation | Footprint upper-right |
| --- | --- | --- | --- |
| `u_lo` | `(3.36, 3.78)` | `FS` | `(787.84, 68.14)` |
| `u_hi` | `(3.36, 132.30)` | `N` | `(787.84, 196.66)` |

Metal2 routing obstructions stop 3 micrometres short of the signal-pin face;
Metal3/Metal4 obstructions span the footprints. Halos are 2 micrometres
horizontal and 0.48 vertical. Recalculate obstructions when moving a macro.

The config includes GDS, LEF, CDL (`spice`), and three Liberty views. The fast
standard-cell corner name (`m40C`) maps to the SRAM's available `m55C` file.
Each instance has two PDN connections: `VDD!` and `VDDARRAY!` to VPWR,
with `VSS!` to VGND.

The tile PDN uses vertical Metal4 stripes: width 2.1, spacing 3.52, pitch
44.96, offset 6.15 micrometres. The 64x64 macro's first left-array VDD and VSS
columns are at x=4.26 and 9.88, width 2.81, matching the guide's left-array
phase. The center/support columns and right array are irregular.
`Project.ExtendPowerStripes` reads the actual LEF geometry to move/add stripes;
its helper is `src/sram/odb_stripes.py`, registered by the root
`librelane_plugin_prism_pdn.py`. The existing every-other-array-column setting
is retained. `pdn_cfg.tcl` omits LibreLane's unused default per-macro grid.

KLayout DRC is enabled with the CMOS5L deck. Magic DRC/illegal-overlap rejection
are disabled for the LEF supply-gap obstruction described in the guide; real
GDS DRC, LVS, power connectivity, IR drop, and timing still need validation.
The stripe helper checks both power nets before publishing zero PDN violations.

## Standalone checks

From the repository root:

```sh
make -C test -f sram_test.mk
make -C test -f sram_test.mk synth_test
```

The first uses Icarus Verilog and the vendored functional PDK models. It checks
all 64 words, distinct low/high data, reads after the clock edge, repeated and
back-to-back reads, partial/zero masks, output hold, disabled reads/writes,
and preservation across reset. The second requires Yosys, checks that exactly
two macro cells survive synthesis, and runs the same test on a flattened
`fsm_main` netlist. Outputs are under ignored `test/sim_build/sram_test/`.
This is functional post-synthesis simulation without P&R or SDF annotation.
The RTL SRAM test also runs in `.github/workflows/test.yaml`.

To use another flattened `fsm_main` netlist (and simulator library arguments
if required):

```sh
make -C test -f sram_test.mk GATES=yes NETLIST=/absolute/path/fsm_main.v
```

`test/Makefile` also includes the SRAM models outside its RTL/GL conditional,
so both versions of the eventual chip-level test can resolve the macros.

## Before chip-level P&R

The chip top `tt_um_protocolemu_dailingw.sv` is still the example adder and does
not instantiate `fsm_main`. The source manifest includes the memory files,
but unreachable modules do not become silicon. `MACROS.instances` and the PDN
regexes currently match standalone `fsm_main` synthesis. Once the chip top
instantiates it, prefix both sets with that instance name (for example,
`u_fsm.u_state_mem.u_banks.u_lo`), and keep the memory outputs used. Add two
more placements and four PDN mappings if another FSM is instantiated.
The existing `state`, `count`, and `timer` outputs are still undriven; their
synthesis warnings are expected until the FSM is implemented.

The GDS workflow still selects **ihp-sg13g2**, whereas these physical views,
DRC deck, and Metal4 PDN target **ihp-sg13cmos5l**. Align the workflow, PDK,
and Tiny Tapeout tile template before running hardening. No chip top or
workflow change was made as part of this memory-only step.

After that integration, run through `Project.ExtendPowerStripes` first. Check
both `check_power_grid -net VPWR -floorplanning` and the VGND equivalent,
inspect Metal4 at both supply regions of each macro, then finish P&R and
review IR drop, DRC/LVS, antenna, and timing reports. Placement/power settings
here are starting values, not completed physical signoff.
