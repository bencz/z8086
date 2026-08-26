export DESIGN_NICKNAME = z8086_chip
export DESIGN_NAME = z8086_chip
export PLATFORM = nangate45

Z8086_SOURCE_LIST := $(shell sed 's|^|/work/|' /work/config/asic/z8086_chip_sources.f)
export VERILOG_FILES = $(Z8086_SOURCE_LIST)
export VERILOG_INCLUDE_DIRS = /work/src/z8086 /work/config/asic/nangate45
export SYNTH_HDL_FRONTEND = slang
export SYNTH_SLANG_ARGS = --allow-use-before-declare

export ADDITIONAL_LEFS = $(PLATFORM_DIR)/lef/fakeram45_1024x32.lef
export ADDITIONAL_LIBS = $(PLATFORM_DIR)/lib/fakeram45_1024x32.lib

export SDC_FILE = /work/config/asic/z8086_chip_nangate45.sdc
export IO_CONSTRAINTS = /work/config/asic/z8086_chip_nangate45_io.tcl
export MACRO_PLACEMENT_TCL = /work/config/asic/nangate45/z8086_macro_placement.tcl
export PDN_TCL = /work/config/asic/nangate45/z8086_pdn.tcl
export PRE_GLOBAL_PLACE_SKIP_IO_TCL = /work/config/asic/nangate45/z8086_physical_regions.tcl
export PRE_GLOBAL_PLACE_TCL = /work/config/asic/nangate45/z8086_physical_regions.tcl
export PRE_RESIZE_TCL = /work/config/asic/nangate45/z8086_pre_resize.tcl
export PRE_GLOBAL_ROUTE_TCL = /work/config/asic/nangate45/z8086_pre_global_route.tcl

# The 3.3 x 2.7 mm die contains four 8x8 SRAM quadrants. Their central
# horizontal and vertical corridors are reserved for CPU, muxing, CTS, and IO.
export DIE_AREA = 0 0 3300 2700
export CORE_AREA = 20.14 21 3279.83 2680
export MACRO_PLACE_HALO = 4 4
export MACRO_PLACE_CHANNEL = 10 10
export RTLMP_ARGS = -target_util 0.20 -report_directory $(OBJECTS_DIR)/rtlmp
export PLACE_DENSITY_LB_ADDON ?= 0.08
export TNS_END_PERCENT = 100
# Global-route capacitance estimates are optimistic for the long SRAM read
# mux wires. Repair to 55% of the Liberty limit so extracted post-route RC
# still closes against the real (unmodified) cell limit.
export CAP_MARGIN = 45
# Global-placement timing/routability repair sees the macro clock and long
# unlegalized wires too early. Physical repair remains enabled after placement.
export GPL_TIMING_DRIVEN = 0
export GPL_ROUTABILITY_DRIVEN = 0
# The skip-IO pass has already produced a connectivity-clustered seed.  Keep
# those real cell coordinates in the IO-aware pass instead of scattering every
# cell back to the die centre.  This flag takes precedence over the ORFS
# force-centre request without replacing the Nangate45 phi coefficients.
export GLOBAL_PLACEMENT_ARGS = -skip_initial_place
export Z8086_INCREMENTAL_IO_PLACE = 1
export REMOVE_ABC_BUFFERS = 1
export SYNTH_MEMORY_MAX_BITS = 32768

# Nangate45 has no CORE ANTENNACELL master.  Requesting antenna repair would
# therefore emit a warning even when the check reports zero violations.  Skip
# only the unavailable repair operation; detail_route.tcl still runs the final
# check_antennas report unconditionally.
export SKIP_ANTENNA_REPAIR = 1
export SKIP_ANTENNA_REPAIR_POST_DRT = 1
