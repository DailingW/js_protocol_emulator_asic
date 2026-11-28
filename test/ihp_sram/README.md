# IHP SRAM behavioural models (vendored)

Copies of `ihp-sg13cmos5l/libs.ref/sg13cmos5l_sram/verilog/` from
[IHP-Open-PDK](https://github.com/IHP-GmbH/IHP-Open-PDK) at commit
`2bbec755dc67ca3db0261c3d6163e15735d66710`, Apache-2.0,
"Copyright 2023 IHP PDK Authors". Both files match that snapshot byte for byte:

- `RM_IHPSG13_1P_64x64_c2_bm_bist.v`: 6-bit address, 64-bit data/mask.
- `RM_IHPSG13_1P_core_behavioral_bm_bist.v`: shared behavioral core.

The test makefiles include `test/sram_models.mk`, which supplies these models
and `-DSIM -DFUNCTIONAL` for
both RTL and netlist simulation. `SIM` excludes the synthesis black box;
`FUNCTIONAL` enables the model's functional clocked interface.

`SRAM_MODEL_DIR` can select another matching model directory. Refresh these
files and the physical views together when the PDK snapshot changes.
