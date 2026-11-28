# Resolve this now, before cocotb includes additional makefiles.
SRAM_MODELS_MK_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
SRAM_MODEL_DIR ?= $(SRAM_MODELS_MK_DIR)/ihp_sram
VERILOG_SOURCES += $(SRAM_MODEL_DIR)/RM_IHPSG13_1P_core_behavioral_bm_bist.v
VERILOG_SOURCES += $(SRAM_MODEL_DIR)/RM_IHPSG13_1P_64x64_c2_bm_bist.v
COMPILE_ARGS += -DSIM -DFUNCTIONAL
