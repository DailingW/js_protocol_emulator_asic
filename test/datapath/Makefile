# Standalone unit tests; do not pull in the unfinished top-level/FSM RTL.
TEST_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
.DEFAULT_GOAL := all

ifeq ($(DUT),)
.PHONY: all rx tx clean
all: rx tx

rx:
	+$(MAKE) --no-print-directory -C $(TEST_DIR) DUT=rx_serializer sim
	$(shell cocotb-config --python-bin) -m cocotb_tools.check_results $(TEST_DIR)/sim_build/rx_serializer/results.xml

tx:
	+$(MAKE) --no-print-directory -C $(TEST_DIR) DUT=tx_parallelizer sim
	$(shell cocotb-config --python-bin) -m cocotb_tools.check_results $(TEST_DIR)/sim_build/tx_parallelizer/results.xml

clean:
	$(RM) -r $(TEST_DIR)/sim_build $(TEST_DIR)/__pycache__
else
ifeq ($(filter $(DUT),rx_serializer tx_parallelizer),)
$(error DUT must be rx_serializer or tx_parallelizer)
endif

SIM := icarus
TOPLEVEL_LANG := verilog
TOPLEVEL := tb_$(DUT)
COCOTB_TEST_MODULES := test_$(DUT)
VERILOG_SOURCES := $(TEST_DIR)/../../src/datapath/$(DUT).sv $(TEST_DIR)/tb_$(DUT).sv
SIM_BUILD := $(TEST_DIR)/sim_build/$(DUT)
COCOTB_RESULTS_FILE := $(SIM_BUILD)/results.xml
FST := -fst
export PYTHONPATH := $(TEST_DIR):$(PYTHONPATH)

include $(shell cocotb-config --makefiles)/Makefile.sim
endif
