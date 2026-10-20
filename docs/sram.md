# SRAM integration

The TT top connects `ibex_area_core`, `sram_logic`, and `sram_banks`:

```text
tt_um_protocolemu_dailingw
    u_ibex                  RV32EC CPU
    u_sram_logic            independent instruction/data bus adapter
    u_mem                   physical SRAM instances
        u_program           RM_IHPSG13_1P_1024x32_c2_bm_bist
        u_data              RM_IHPSG13_1P_512x32_c2_bm_bist
```

| File | Purpose |
| --- | --- |
| `src/sram.sv` | Empty macro declarations for synthesis. |
| `src/sram_banks.sv` | The actual macro instances, BIST/delay tie-offs, and byte masks. |
| `src/sram_logic.sv` | Address decoding, SRAM enables, grants, response timing, and errors. |
| `test/ihp_sram/*.v` | IHP functional implementations of the same macro names for simulation. |

`SIM` hides the black boxes during simulation; `FUNCTIONAL` enables the copied
PDK models. The synthesis source list includes the declarations, adapter, and
bank wrapper, and excludes the functional models. Vendor Ibex RTL is unchanged.

## Address map and access policy

| Byte addresses | Size | CPU interface | Contents |
| --- | --- | --- | --- |
| `0x00000000`–`0x00000fff` | 4 KiB | Instruction fetch, read-only | Instructions and interrupt-handler code |
| `0x10000000`–`0x100007ff` | 2 KiB | Data loads/stores | Constants, globals, stack, buffers |

The paths are strictly separate. Data loads/stores into program addresses and
instruction fetches from data addresses produce errors. Firmware's linker
script must put `.text` in program SRAM and `.rodata`, `.data`, `.bss`, and stack
in data SRAM, including compiler-generated constant tables. The current reset
PC is `0x00000080`.

The adapter checks the full address range and word alignment before enabling a
bank. Ibex presents word-aligned byte addresses even for byte/halfword accesses;
byte enables select the affected lanes. SRAM word indices use instruction bits
`[11:2]` and data bits `[10:2]`. Invalid accesses cannot wrap into a valid word.

## Handshakes and timing

While `rst_n` and `ena` are high, each interface grants requests immediately.
The SRAM samples its enable, address, and write controls at the acceptance edge.
After that edge, the adapter's registered response-valid/error signals line up
with the SRAM's clocked output, ready for Ibex to consume at the following edge.
Each bank can accept one operation per clock independently, including concurrent
instruction fetches and data accesses. Consecutive response-valid cycles can
represent consecutive accepted requests.

Stores receive completion responses too; their return data is zero. Invalid
requests are granted and receive an error response with zero data, without
enabling the SRAM. This avoids leaving the CPU waiting indefinitely. Reset
clears response state. Lowering `ena` stops new grants while allowing an already
accepted operation to respond. Reset does not clear SRAM contents.

## Current top-level pins

`ui_in[6]` supplies the external interrupt and `ui_in[7]` supplies debug request;
both are gated by `ena`. The other `ui_in` bits and `uio_in[3:0]` are reserved for
future interfaces. The old response-byte loader and externally driven memory
handshakes have been removed.

`uio_in[7:4]` selects the observation byte on `uo_out`: selections 0–3 show
instruction address bytes, 4–7 data address bytes, and 8–11 write-data bytes.
Selection 12 shows `{core_sleep, data_be[3:0], data_we, data_req, instr_req}`.
Selection 13 shows `{4'b0, double_fault_seen, alert_major_bus,
alert_major_internal, alert_minor}`. Selection 14 shows `{2'b0, data_err,
instr_err, data_rvalid, instr_rvalid, data_gnt, instr_gnt}`. Selection 15 is zero.
All bidirectional pins remain inputs (`uio_oe = 0`).

## Tests

Run from `test/` using the existing OSS CAD Suite and its bundled cocotb:

```sh
make -f Makefile.sram                 # Raw SRAM models and bank wrapper
make -f Makefile.sram SRAM_TEST=logic # Adapter plus real SRAM models
make                                 # Full Ibex + adapter + banks, using Verilator
```

No separate Python environment is needed. The full CPU test needs Verilator
5.036 or newer and a C++ compiler; the bank/adapter tests use Icarus Verilog.
The normal Makefile generates the patched Ibex source copies when needed.
It also sets the bundled Python library search path for the macOS simulator.

`Makefile.sram` selects a small testbench without compiling Ibex. Both Makefiles
include `sram_models.mk`, a shared list of the three models and the
`-DSIM -DFUNCTIONAL` flags. `.mk` simply identifies shared Makefile settings.

The adapter test covers simultaneous and consecutive requests, byte masks,
address boundaries, cross-bank and invalid-address errors, disabled requests,
and reset/response timing. The CPU smoke test preloads
`test/programs/sram_smoke.hex`, executes word/byte/halfword operations, checks the
CPU's externally observed transactions, and waits for successful completion in
`WFI`. Its RV32E assembly source is beside the hex file; running the test does
not require the RISC-V software toolchain.

## Remaining integration

The top has no external program loader yet. CPU program writes are disabled;
program write-enable, byte enables, and write data are tied low. The tests fill
program SRAM through the functional model hierarchy, which provides no loading
mechanism on manufactured hardware. The intended next step is an SPI loader
that can initialize both banks while keeping Ibex in reset, then release the CPU.
A gate-level boot test also needs that hardware loading path; only RTL boot is
validated at this stage.

Physical integration is still required in `src/config.json`: macro LEF/GDS/CDL
and timing views, placement, power-pin connections, and the power grid. The
expected instance paths are `u_mem.u_program` and `u_mem.u_data`; verify them
against the synthesized hierarchy. Passing RTL tests does not validate SRAM
placement or power connectivity.
