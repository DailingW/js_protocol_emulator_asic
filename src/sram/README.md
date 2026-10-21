# SRAM PDN setup and checks

This directory contains the SRAM RTL and the physical power-grid helper for the
IHP SG13CMOS5L Tiny Tapeout tile. See [SRAM integration](../../docs/sram.md) for the
CPU address map, bus timing, functional tests, and the missing hardware loader.

## Files and flow

| File | Role |
| --- | --- |
| [sram.sv](sram.sv) | Black-box declarations of the two SRAM macros for synthesis. |
| [sram_banks.sv](sram_banks.sv) | Physical macro instances, byte masks, and BIST/delay tie-offs. |
| [sram_logic.sv](sram_logic.sv) | Ibex instruction/data bus adapter. |
| [pdn_cfg.tcl](pdn_cfg.tcl) | Tile PDN configuration without the default per-macro grid. |
| [odb_stripes.py](odb_stripes.py) | Extends Metal4 power stripes across SRAM supply columns, checks connectivity, and updates PDN metrics. |
| [../../librelane_plugin_prism_pdn.py](../../librelane_plugin_prism_pdn.py) | Registers `Project.ExtendPowerStripes` and passes configuration to the helper. |
| [../../scripts/prepare_ibex.py](../../scripts/prepare_ibex.py) | Prepares the generated Ibex sources before config generation and synthesis. |
| [../config.json](../config.json) | Macro views, placement, supply mappings, obstructions, and the custom-step hook. |

The plugin must stay at the **repository root** so LibreLane discovers its
`librelane_plugin_*` module when launched there with `python3 -m librelane`.
It resolves the helper relative to its own file as `src/sram/odb_stripes.py`.
Run the helper through LibreLane/OpenROAD; ordinary Python does not supply its
`odb`, `openroad`, or LibreLane `reader` imports.

`sram.sv` contains intentionally empty macro declarations: Verilator otherwise
reports unused inputs and undriven outputs when linting this synthesis source.
[../ibex_lint.vlt](../ibex_lint.vlt) waives `UNUSEDSIGNAL` and `UNDRIVEN` only for
that file. The adapter, bank wrapper, and functional models retain their normal
checks; the actual SRAM behavior comes from the PDK models/macros.

The sequence is:

```text
Odb.SetPowerConnections / Odb.ManualMacroPlacement
    -> OpenROAD.GeneratePDN (src/sram/pdn_cfg.tcl)
    -> Project.ExtendPowerStripes (src/sram/odb_stripes.py)
    -> remaining Classic placement, routing, extraction, and signoff steps
```

The tile uses Metal1 cell rails and vertical Metal4 stripes. Default `pdngen`
stripes are cut around the SRAMs. The custom step chooses actual SRAM power
columns, replaces/adds stripes and rail vias, and keeps power-pin boxes full
height. Removing the unused default per-macro grid in `pdn_cfg.tcl` avoids an
empty-grid `PDN-0233` error before the custom step can run.

After extending the grid, the helper verifies that both SRAMs have `VDD!` and
`VDDARRAY!` on VPWR and `VSS!` on VGND. It runs `check_power_grid` for both nets
with `-floorplanning`, which ignores unplaced logic cells while retaining fixed
macros. Only after both checks pass does it replace the earlier
`design__power_grid_violation__count` metrics with zero. An actual connectivity
error fails the step. Keep `Checker.PowerGridViolations` enabled; the earlier
workaround that skipped it is no longer needed.

## Current configuration

All coordinates below are in micrometres. The authoritative values are in
[../config.json](../config.json); do not edit generated `config_merged.json`.

| Instance | Macro | Lower-left position | Orientation | Size |
| --- | --- | --- | --- | --- |
| `u_mem.u_program` | `RM_IHPSG13_1P_1024x32_c2_bm_bist` | `(3.36, 3.78)` | `FS` | `416.64 x 336.46` |
| `u_mem.u_data` | `RM_IHPSG13_1P_512x32_c2_bm_bist` | `(452.96, 3.78)` | `FS` | `416.64 x 191.34` |

Both macros are side by side, with their signal pins facing the top of the tile.
The project is a `6x4` tile (`1289.28 x 710.64`). `MACROS` selects each macro's
LEF, GDS, CDL through the `spice` field, and Liberty files under
`pdk_dir::libs.ref/sg13cmos5l_sram/`. Each has typical, fast, and slow timing views;
the fast SRAM file is characterized at `-55 C`, while the corresponding standard
cell corner is `-40 C`.

The custom flow hook and Tcl path are:

```json
{
  "meta": {
    "flow": "Classic",
    "substituting_steps": {
      "+OpenROAD.GeneratePDN": "Project.ExtendPowerStripes"
    }
  },
  "PDN_CFG": "dir::sram/pdn_cfg.tcl"
}
```

The supply mappings must match the synthesized instance names:

```json
"PDN_MACRO_CONNECTIONS": [
  "^u_mem\\.u_program$ VPWR VGND VDD! VSS!",
  "^u_mem\\.u_program$ VPWR VGND VDDARRAY! VSS!",
  "^u_mem\\.u_data$ VPWR VGND VDD! VSS!",
  "^u_mem\\.u_data$ VPWR VGND VDDARRAY! VSS!"
]
```

The tile grid, macro halos, and helper settings are:

```json
"FP_PDN_VWIDTH": 2.1,
"FP_PDN_VSPACING": 3.52,
"FP_PDN_VPITCH": 44.96,
"FP_PDN_VOFFSET": 6.15,
"FP_PDN_MULTILAYER": 0,
"FP_MACRO_HORIZONTAL_HALO": 2.0,
"FP_MACRO_VERTICAL_HALO": 0.48,
"EXTEND_STRIPES_SRAM_ALL_COLUMNS": false,
"EXTEND_STRIPES_SRAM_ARRAY_EVERY_OTHER": true,
"EXTEND_STRIPES_PIN_FACE_MARGIN": 0
```

`VSPACING` is edge-to-edge: `2.1 + 3.52 = 5.62` between the centres of a tile
VPWR/VGND stripe pair. The helper may move stripes onto the SRAM's actual columns
and add pairs; inspect its output rather than assuming every original stripe
already aligns. It defaults to Metal4, `0.24` clearance, and `10` via-stack pitch.
`SRAM_ALL_COLUMNS` and `SRAM_ARRAY_EVERY_OTHER` cannot both be true.
`PIN_FACE_MARGIN=0` retains rail vias near the signal-pin edge; revisit this if
routing/DRC reports show pin-access conflicts.

The signal-routing obstructions are:

```json
"ROUTING_OBSTRUCTIONS": [
  "Metal2 3.36 3.78 420.00 337.24",
  "Metal3 3.36 3.78 420.00 340.24",
  "Metal4 3.36 3.78 420.00 340.24",
  "Metal2 452.96 3.78 869.60 192.12",
  "Metal3 452.96 3.78 869.60 195.12",
  "Metal4 452.96 3.78 869.60 195.12"
]
```

Metal2 leaves a `3 um` opening at each macro's top signal-pin edge. These
obstructions constrain signal routing; the custom helper explicitly constructs
the special power routes. If placement, orientation, or macro size changes,
recalculate the rectangles and repeat both connectivity and GUI checks. The
stripe helper supports `N`/`FS` (`R0`/`MX`) orientations.

## Enter the local tool environment

The existing workspace has this layout:

```text
TINYTAPEOUT/
  librelane/shell.nix
  pdk/IHP-Open-PDK/ihp-sg13cmos5l/
  js_protocol_emulator_asic/
    tt/                 # Tiny Tapeout support-tools checkout
    .venv-ibex/          # Existing Python environment for tt_tool.py
    librelane_plugin_prism_pdn.py
    src/config.json
    src/sram/
```

Start in the project root, with any active Python virtual environment
deactivated, then enter the Nix shell:

```bash
cd /Users/dailingwu/Documents/TINYTAPEOUT/js_protocol_emulator_asic
nix-shell ../librelane/shell.nix
export PDK_ROOT="$PWD/../pdk/IHP-Open-PDK"
export PDK=ihp-sg13cmos5l
python3 -m librelane --version
openroad -version
```

Adjust the first path on another machine. Nix is installed system-wide. If a
terminal opened before installation cannot find `nix-shell`, open a fresh
terminal or source `/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh`.

Use Nix's Python for LibreLane. The existing `.venv-ibex` provides the support
tool's Python dependencies (including Chevron); invoke it explicitly for the
next command rather than activating it over the Nix shell. No additional venv
or pip installation of LibreLane is needed. The support-tools checkout must
contain the `ihp-sg13cmos5l` `6x4` template.

## Generate the merged configuration

From the project root inside the Nix shell:

```bash
python3 scripts/prepare_ibex.py
PATH="$PWD/.venv-ibex/bin:$PATH" \
  .venv-ibex/bin/python tt/tt_tool.py --create-user-config --ihp
```

This regenerates `src/user_config.json` and `src/config_merged.json` from
`info.yaml`, the tile template, and `src/config.json`. Run it again after editing
the source list or configuration. In particular, the source list must now use
`sram/sram.sv`, `sram/sram_logic.sv`, and `sram/sram_banks.sv`.
Both generated JSON files are ignored by Git; CI regenerates them too.

## Run only through the extended PDN

Use a fresh run name when changing RTL, macro placement, or PDN settings. This
example uses `pdn_check_sram`; choose another name for another experiment.

```bash
PDN_RUN=pdn_check_sram
mkdir -p "runs/$PDN_RUN"
python3 -m librelane \
  --manual-pdk --pdk "$PDK" --pdk-root "$PDK_ROOT" \
  --run-tag "$PDN_RUN" --force-run-dir "$PWD/runs/$PDN_RUN" \
  --to Project.ExtendPowerStripes \
  src/config_merged.json
```

The explicit run directory keeps results in the repository's `runs/`, rather
than `src/runs/`. This runs synthesis and floorplanning through the custom power
step, without completing placement/routing. The step log should contain:

```text
[INFO PSM-0040] All shapes on net VPWR are connected.
[INFO PSM-0040] All shapes on net VGND are connected.
```

The helper also emits zero violation metrics after these checks pass. Review
`runs/$PDN_RUN/*-project-extendpowerstripes/state_out.json` and its
`project-extendpowerstripes.log` for the actual output. Step numbers can change.
An old `*-openroad-generatepdn/*-grid-errors.rpt` describes the grid **before**
extension, so it can still contain errors even when the later check passes.

The directory reorganization was verified with a fresh local run at
`runs/pdn_reorg_check/`: synthesis through the extension step passed and both
power-grid violation counts were zero. Set `PDN_RUN=pdn_reorg_check` to inspect
that existing database with the GUI command below.

## Inspect the extended PDN in the GUI

From the same project root and Nix shell, after the partial run succeeds:

```bash
openroad -gui -no_init -db \
  runs/"$PDN_RUN"/*-project-extendpowerstripes/tt_um_protocolemu_dailingw.odb
```

If opening another terminal, re-enter the Nix shell and set
`PDN_RUN=pdn_check_sram` again. Open the database from the **extension step**,
not `OpenROAD.GeneratePDN`. If a reused run contains multiple extension steps,
select the intended `.odb` explicitly instead of using the wildcard.

In the display controls, enable Metal4, power/ground special nets, instances,
and macro pins. Inspect VPWR and VGND separately and zoom into both macros:

1. Confirm that selected power stripes overlap the matching supply-pin columns,
   with their centres aligned, and avoid the opposite supply columns.
2. Confirm that **both** `VDD!` and `VDDARRAY!` receive VPWR and `VSS!` receives
   VGND on each SRAM. Highlighting the matching net/pin makes this clearer than
   viewing every layer at once.
3. Inspect the Metal1-to-Metal4 rail via stacks outside the macro footprints and
   the signal-pin escape area along each macro's top edge.

Not every available SRAM column needs a stripe with the selected
every-other-array-pair setting. A screenshot alone cannot establish electrical
connectivity; use the checks as well. Saved local views are in
[sramPDN1.png](../../docs/sramPDN1.png) and
[sramPDN2.png](../../docs/sramPDN2.png).

In the OpenROAD **Tcl console**, rerun:

```tcl
check_power_grid -net VPWR -floorplanning -error_file runs/pdn_check_sram/VPWR-grid-errors.rpt
check_power_grid -net VGND -floorplanning -error_file runs/pdn_check_sram/VGND-grid-errors.rpt
```

Adjust the report directory if you chose another run name. Both commands should
report all shapes connected without unconnected-instance warnings. This checks
power connectivity at floorplanning; it does not establish IR drop, timing,
antenna closure, or final DRC/LVS.

## Continue to the IR-drop report

The logic cells are still unplaced at the PDN checkpoint. LibreLane's normal
IR-drop step needs the routed database and extracted SPEF, so continue the same
run through placement, routing, and extraction:

```bash
python3 -m librelane \
  --manual-pdk --pdk "$PDK" --pdk-root "$PDK_ROOT" \
  --run-tag "$PDN_RUN" --force-run-dir "$PWD/runs/$PDN_RUN" \
  --from Odb.RemovePDNObstructions --to OpenROAD.IRDropReport \
  src/config_merged.json

cat runs/"$PDN_RUN"/*-openroad-irdropreport/irdrop.rpt
```

This resumes from the run's latest state and stops before GDS generation and
later signoff checks. Resume only if the inputs still match the checkpoint;
otherwise generate a fresh run. `RUN_IRDROP_REPORT` defaults to true in Classic.
Inspect `Worstcase voltage`, `Average IR drop`, and `Worstcase IR drop`, plus the
per-instance `net-VPWR.csv` and `net-VGND.csv` files in that step directory.
The result depends on modeled power/activity and supply-source locations;
another project's sub-millivolt result is not a pass threshold for this design.

## GitHub workflow and remaining concerns

[../../.github/workflows/gds.yaml](../../.github/workflows/gds.yaml) prepares
Ibex, regenerates the merged config, and invokes the full Tiny Tapeout hardening
action. Running `python -m librelane` from the root lets that flow find the same
plugin. Commit the root plugin, this directory, and the updated source/config
references together, including the saved GUI images linked above. The `tt/`
checkout, venv, Python caches, and `runs/` are ignored local tool or generated
data, not additional SRAM design sources to upload.

Download the **GDS_logs** artifact and inspect
`runs/wokwi/*-openroad-irdropreport/irdrop.rpt` once CI reaches that step. CI does
not perform the visual inspection for you, or apply a design-specific IR-drop
budget just because the report was generated.

The local PDN check has been exercised with LibreLane `3.0.16`; the current
`ihp-cmos5l` GDS action defaults to `3.1.0.dev3`. Tool/PDK versions can therefore
differ between local runs and CI. Record the resolved configuration and
versions when comparing results, and review the copied Tcl when upgrading the
flow. Historical run configs/logs retain the paths and tool settings used when
they were created; moving files does not rewrite those snapshots.

Full routed DRC, antenna results, LVS, timing, and numerical IR drop remain to be
validated. `RUN_KLAYOUT_DRC` is currently disabled in the template config, so a
green GDS job alone does not claim that check ran. The top also still needs a
hardware program loader before it can boot on silicon. Keep Classic's antenna
checking/repair enabled; extra SRAM pin diodes should be driven by routed antenna
results rather than copied from unrelated PRISM steps.

## References

- [Original SRAM integration guide](https://kdp1965.github.io/ihp-um-janestreet-prism/ihp_sram_macro.html)
- [PRISM reference design](https://github.com/kdp1965/ihp-um-janestreet-prism)
- [LibreLane step substitutions](https://librelane.readthedocs.io/en/latest/usage/writing_custom_flows.html#by-substituting-steps)
- [OpenROAD power-grid checks and IR analysis](https://openroad.readthedocs.io/en/latest/main/src/psm/README.html)
- [Tiny Tapeout CMOS5L GDS action](https://github.com/TinyTapeout/tt-gds-action/blob/ihp-cmos5l/action.yml)
