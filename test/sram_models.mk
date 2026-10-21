# Shared by the full-project Makefile and the standalone SRAM test.
# SIM hides src/sram/sram.sv's black boxes; FUNCTIONAL enables the PDK models.
SRAM_MODEL_DIR ?= $(PWD)/ihp_sram
VERILOG_SOURCES += $(SRAM_MODEL_DIR)/RM_IHPSG13_1P_core_behavioral_bm_bist.v
VERILOG_SOURCES += $(SRAM_MODEL_DIR)/RM_IHPSG13_1P_1024x32_c2_bm_bist.v
VERILOG_SOURCES += $(SRAM_MODEL_DIR)/RM_IHPSG13_1P_512x32_c2_bm_bist.v
COMPILE_ARGS += -DSIM -DFUNCTIONAL
