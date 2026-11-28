# Standalone SRAM smoke test, including the actual fsm_main memory instance.
# Run: make -C test -f sram_test.mk
# Reuse a flattened fsm_main netlist: ... GATES=yes NETLIST=/path/to/fsm_main.v
TEST_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
SRC_DIR := $(TEST_DIR)/../src
.DEFAULT_GOAL := sram_test

IVERILOG ?= iverilog
VVP ?= vvp
YOSYS ?= yosys
GATES ?= no
RTL_SOURCES := $(SRC_DIR)/sram/sram.sv \
               $(SRC_DIR)/sram/sram_banks.sv \
               $(SRC_DIR)/sram/sram_logic.sv \
               $(SRC_DIR)/fsm_main.sv
SYNTH_DIR := $(TEST_DIR)/sim_build/sram_test
SYNTH_NETLIST := $(SYNTH_DIR)/fsm_main.v

ifeq ($(GATES),yes)
ifndef NETLIST
$(error Set NETLIST to a synthesized fsm_main netlist for GATES=yes)
endif
VERILOG_SOURCES := $(NETLIST)
BUILD_DIR := $(TEST_DIR)/sim_build/sram_test/gl
else
VERILOG_SOURCES := $(RTL_SOURCES)
BUILD_DIR := $(TEST_DIR)/sim_build/sram_test/rtl
endif

# Shared with the project's RTL and GL cocotb tests.
include $(TEST_DIR)/sram_models.mk
VERILOG_SOURCES += $(TEST_DIR)/sram_test.sv

.PHONY: sram_test synth_test
sram_test: $(BUILD_DIR)/sim.vvp
	$(VVP) -N $<

# Also verify that synthesis preserves two black boxes and simulate the result
# using the same PDK models. This is post-synthesis, without P&R or SDF timing.
synth_test: $(SYNTH_NETLIST)
	+$(MAKE) -f $(TEST_DIR)/sram_test.mk GATES=yes NETLIST=$(SYNTH_NETLIST) sram_test

$(SYNTH_NETLIST): $(RTL_SOURCES) $(TEST_DIR)/sram_test.mk
	mkdir -p $(SYNTH_DIR)
	$(YOSYS) -Q -T -q -l $(SYNTH_DIR)/synth.log -p 'read_verilog -sv $(RTL_SOURCES); synth -top fsm_main -flatten; select -assert-count 2 t:RM_IHPSG13_1P_64x64_c2_bm_bist; write_json $(SYNTH_DIR)/fsm_main.json; write_verilog -noattr $@'

$(BUILD_DIR)/sim.vvp: $(VERILOG_SOURCES) $(TEST_DIR)/sram_test.mk $(TEST_DIR)/sram_models.mk
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall $(COMPILE_ARGS) -s sram_test -o $@ $(VERILOG_SOURCES)
