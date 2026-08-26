export DESIGN_NICKNAME = z8086
export DESIGN_NAME = z8086
export PLATFORM = nangate45

Z8086_SOURCE_LIST := $(shell sed 's|^|/work/|' /work/config/asic/z8086_core_sources.f)
export VERILOG_FILES = $(Z8086_SOURCE_LIST)
export VERILOG_INCLUDE_DIRS = /work/src/z8086
export SYNTH_HDL_FRONTEND = slang
export SYNTH_SLANG_ARGS = --allow-use-before-declare

export SDC_FILE = /work/config/asic/z8086_core_nangate45.sdc
export IO_CONSTRAINTS = /work/config/asic/z8086_core_nangate45_io.tcl
export PDN_TCL = /work/config/asic/nangate45/z8086_core_pdn.tcl
export PRE_GLOBAL_PLACE_SKIP_IO_TCL = /work/config/asic/nangate45/z8086_core_physical_regions.tcl
export PRE_GLOBAL_PLACE_TCL = /work/config/asic/nangate45/z8086_core_physical_regions.tcl
export PRE_GLOBAL_ROUTE_TCL = /work/config/asic/nangate45/z8086_pre_global_route.tcl

# The logic-only core is deliberately compact.  The former 500 um square left
# only 6% utilization, lengthening clock/I/O wiring without buying routability.
# Keep both rectangles overridable so timing experiments remain reproducible.
export DIE_AREA = $(Z8086_EXTERNAL_DIE_AREA)
export CORE_AREA = $(Z8086_EXTERNAL_CORE_AREA)
export PLACE_DENSITY_LB_ADDON ?= 0.10
export TNS_END_PERCENT = 100
export CAP_MARGIN = 45
export REMOVE_ABC_BUFFERS = 1
export SYNTH_MEMORY_MAX_BITS = 32768
export GLOBAL_PLACEMENT_ARGS = -skip_initial_place

# Nangate45 contains no antenna diode master. Detail routing still performs
# the mandatory final antenna check; only the unavailable repair is skipped.
export SKIP_ANTENNA_REPAIR = 1
export SKIP_ANTENNA_REPAIR_POST_DRT = 1
