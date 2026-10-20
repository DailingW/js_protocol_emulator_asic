# Makefile
# See https://docs.cocotb.org/en/stable/quickstart.html for more info

# defaults
ifeq ($(GATES),yes)
SIM ?= icarus
else
SIM ?= verilator
endif
FST ?= -fst # Use more efficient FST format
TOPLEVEL_LANG ?= verilog
SRC_DIR = $(PWD)/../src
# Keep package definitions before the RTL that imports them; match info.yaml.
PROJECT_SOURCES = \
  tt_um_protocolemu_dailingw.sv \
  vendor/ibex/rtl/ibex_pkg.sv \
  vendor/ibex/rtl/ibex_cheriot_pkg.sv \
  vendor/ibex/vendor/lowrisc_ip/ip/prim_generic/rtl/prim_ram_1p_pkg.sv \
  vendor/ibex/vendor/lowrisc_ip/ip/prim/rtl/prim_secded_pkg.sv \
  vendor/ibex/vendor/lowrisc_ip/ip/prim/rtl/prim_util_pkg.sv \
  vendor/ibex/vendor/lowrisc_ip/ip/prim/rtl/prim_cipher_pkg.sv \
  vendor/ibex/vendor/lowrisc_ip/ip/prim/rtl/prim_count_pkg.sv \
  vendor/ibex/vendor/lowrisc_ip/ip/prim/rtl/prim_mubi_pkg.sv \
  vendor/ibex/vendor/lowrisc_ip/ip/prim_generic/rtl/prim_buf.sv \
  vendor/ibex/vendor/lowrisc_ip/ip/prim_generic/rtl/prim_clock_gating.sv \
  vendor/ibex/rtl/ibex_alu.sv \
  vendor/ibex/rtl/ibex_compressed_decoder.sv \
  vendor/ibex/rtl/ibex_controller.sv \
  vendor/ibex/rtl/ibex_counter.sv \
  vendor/ibex/rtl/ibex_cs_registers.sv \
  vendor/ibex/rtl/ibex_csr.sv \
  vendor/ibex/rtl/ibex_decoder.sv \
  generated/ibex_ex_block.sv \
  vendor/ibex/rtl/ibex_fetch_fifo.sv \
  vendor/ibex/rtl/ibex_id_stage.sv \
  vendor/ibex/rtl/ibex_if_stage.sv \
  vendor/ibex/rtl/ibex_load_store_unit.sv \
  vendor/ibex/rtl/ibex_prefetch_buffer.sv \
  vendor/ibex/rtl/ibex_wb_stage.sv \
  vendor/ibex/rtl/ibex_register_file_ff.sv \
  vendor/ibex/rtl/ibex_core.sv \
  generated/ibex_top.sv \
  ibex_area_core.sv \
  sram.sv sram_logic.sv sram_banks.sv

# SRAM behavioural models are needed by both RTL and gate-level simulation.
include $(PWD)/sram_models.mk

ifneq ($(GATES),yes)

# RTL simulation:
ifneq ($(SIM),verilator)
$(error Ibex RTL requires Verilator; run make SIM=verilator)
endif
SIM_BUILD				= sim_build/rtl
VERILOG_SOURCES += $(addprefix $(SRC_DIR)/,$(PROJECT_SOURCES))
COMPILE_ARGS += --timing -DSYNTHESIS $(SRC_DIR)/ibex_lint.vlt
CUSTOM_COMPILE_DEPS += $(SRC_DIR)/ibex_lint.vlt
VERILOG_INCLUDE_DIRS += $(SRC_DIR)/vendor/ibex/vendor/lowrisc_ip/ip/prim/rtl
VERILOG_INCLUDE_DIRS += $(SRC_DIR)/vendor/ibex/vendor/lowrisc_ip/dv/sv/dv_utils
CUSTOM_SIM_DEPS += $(PWD)/programs/sram_smoke.hex
# On macOS, the bundled Python library's dependencies need the suite's lib
# directory when loaded by a simulator executable built outside that suite.
ifeq ($(shell uname -s),Darwin)
SIM_CMD_PREFIX += env DYLD_FALLBACK_LIBRARY_PATH="$(dir $(shell cocotb-config --libpython)):$(DYLD_FALLBACK_LIBRARY_PATH)"
endif

else

# Gate level simulation:
SIM_BUILD				= sim_build/gl
COMPILE_ARGS    += -DGL_TEST
VERILOG_SOURCES += $(PDK_ROOT)/ihp-sg13cmos5l/libs.ref/sg13cmos5l_io/verilog/sg13cmos5l_io.v
VERILOG_SOURCES += $(PDK_ROOT)/ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell/verilog/sg13cmos5l_stdcell.v

# this gets copied in by the GDS action workflow
VERILOG_SOURCES += $(PWD)/gate_level_netlist.v

endif

# Allow sharing configuration between design and testbench via `include`:
COMPILE_ARGS 		+= -I$(SRC_DIR)

# Include the testbench sources:
VERILOG_SOURCES += $(PWD)/tb.v
TOPLEVEL = tb

# List test modules to run, separated by commas and without the .py suffix:
COCOTB_TEST_MODULES = test

# include cocotb's make rules to take care of the simulator setup
include $(shell cocotb-config --makefiles)/Makefile.sim

# Generate the patched Ibex copies automatically on a fresh checkout.
$(SRC_DIR)/generated/ibex_top.sv: $(PWD)/../scripts/prepare_ibex.py $(SRC_DIR)/vendor/ibex/rtl/ibex_top.sv
	python3 $(PWD)/../scripts/prepare_ibex.py

$(SRC_DIR)/generated/ibex_ex_block.sv: $(SRC_DIR)/generated/ibex_top.sv $(SRC_DIR)/vendor/ibex/rtl/ibex_ex_block.sv
	python3 $(PWD)/../scripts/prepare_ibex.py
