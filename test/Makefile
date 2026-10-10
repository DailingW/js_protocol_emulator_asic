# Makefile
# See https://docs.cocotb.org/en/stable/quickstart.html for more info

# defaults
SIM ?= icarus
FST ?= -fst # Use more efficient FST format
TOPLEVEL_LANG ?= verilog
SRC_DIR = $(PWD)/../src
PROJECT_SOURCES = tt_um_protocolemu_dailingw.sv fifo.sv

ifneq ($(GATES),yes)

# RTL simulation:
SIM_BUILD				= sim_build/rtl
VERILOG_SOURCES += $(addprefix $(SRC_DIR)/,$(PROJECT_SOURCES))

else

# Gate level simulation:
SIM_BUILD				= sim_build/gl
COMPILE_ARGS    += -DGL_TEST
COMPILE_ARGS    += -DFUNCTIONAL
COMPILE_ARGS    += -DSIM
VERILOG_SOURCES += $(PDK_ROOT)/ihp-sg13g2/libs.ref/sg13g2_io/verilog/sg13g2_io.v
VERILOG_SOURCES += $(PDK_ROOT)/ihp-sg13g2/libs.ref/sg13g2_stdcell/verilog/sg13g2_stdcell.v

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

# Cocotb's default `all` already runs `sim` (the single-UART bench).
# Add the dual RTL bench to normal runs, but keep gate-level runs separate.
ifneq ($(GATES),yes)
all: dual-test
endif

all:
	"$(PYTHON_BIN)" -m cocotb_tools.check_results $(COCOTB_RESULTS_FILE)

.PHONY: dual-test fifo-test
dual-test:
	$(MAKE) -f Makefile.dual
	"$(PYTHON_BIN)" -m cocotb_tools.check_results results_dual.xml

fifo-test:
	mkdir -p sim_build/fifo
	iverilog -g2012 -s fifo_tb -o sim_build/fifo/sim.vvp $(SRC_DIR)/fifo.sv fifo_tb.sv
	vvp sim_build/fifo/sim.vvp
