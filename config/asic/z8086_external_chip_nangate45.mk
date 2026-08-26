export DESIGN_NICKNAME = z8086_external_chip_core
export DESIGN_NAME = z8086_external_chip_core
export PLATFORM = nangate45

Z8086_SOURCE_LIST := $(shell sed 's|^|/work/|' /work/config/asic/z8086_external_chip_sources.f)
export VERILOG_FILES = $(Z8086_SOURCE_LIST)
export VERILOG_INCLUDE_DIRS = /work/src/z8086 /work/src/asic
export SYNTH_HDL_FRONTEND = slang
export SYNTH_SLANG_ARGS = --allow-use-before-declare

# These macros represent only the placement envelope that TSMC IO/ESD/corner
# IP will occupy.  They are physical-only and are never advertised as
# fabricable cells.
export ADDITIONAL_LEFS = /work/build/asic-placeholder-ip/z8086_placeholder_io.lef
export ADDITIONAL_GDS = /work/build/asic-placeholder-ip/z8086_placeholder_io.gds

export SDC_FILE = /work/config/asic/z8086_external_chip_nangate45.sdc
export IO_CONSTRAINTS = /work/config/asic/z8086_external_chip_nangate45_io.tcl
export PDN_TCL = /work/config/asic/nangate45/z8086_external_chip_pdn.tcl
export FASTROUTE_TCL = /work/config/asic/nangate45/z8086_external_chip_fastroute.tcl
export PRE_GLOBAL_PLACE_SKIP_IO_TCL = /work/config/asic/nangate45/z8086_external_chip_physical.tcl
export PRE_GLOBAL_PLACE_TCL = /work/config/asic/nangate45/z8086_external_chip_physical.tcl
export POST_GLOBAL_PLACE_TCL = /work/config/asic/nangate45/z8086_release_cpu_guides.tcl
export PRE_GLOBAL_ROUTE_TCL = /work/config/asic/nangate45/z8086_pre_global_route.tcl

# This trial die is intentionally pad-limited.  Rows, taps, endcaps and the
# core PDN are created only in the central timing island; the surrounding area
# is reserved for process-specific IO, ESD and power-ring integration.
export DIE_AREA = 0 0 1000 1000
export CORE_AREA = 340.10 343.0 659.87 656.6
# Give the pin-dense gate ROM and datapath enough whitespace for detailed
# access.  RePlAce adds this value to its measured lower bound, producing an
# effective target near 49% for this floorplan without per-region overrides.
export PLACE_DENSITY_LB_ADDON ?= 0.45
export TNS_END_PERCENT = 100
export CAP_MARGIN = 45
export REMOVE_ABC_BUFFERS = 1
export SYNTH_MEMORY_MAX_BITS = 32768
export GLOBAL_PLACEMENT_ARGS = -skip_initial_place

# Keep six compact functional guides active in both placement passes. Shared
# exchange logic is seeded in the seventh central area but remains the movable
# base population required by RePlAce.
# Unconstrained timing refinement reduced HPWL but mixed decoder, ALU and BIU
# cells into one unreviewable blob.  Timing is instead optimized inside and at
# the boundaries of the persistent SUGGESTED regions, then proven post-route.
export Z8086_TIMING_REFINEMENT = 0
export GPL_TIMING_DRIVEN = 0
export GPL_ROUTABILITY_DRIVEN = 0

# The CPU island is only 320 um wide.  A widened/non-default clock rule adds
# congestion without useful wire-delay benefit at this scale and FastRoute
# otherwise disables it dynamically (which is a fatal warning in this flow).
# Keep clock buffering/repair, but route the tree with the characterized
# default metal rules and prove the result again in extracted post-route STA.
export CTS_ARGS = -sink_clustering_enable -repair_clock_nets -apply_ndr none

export SKIP_ANTENNA_REPAIR = 1
export SKIP_ANTENNA_REPAIR_POST_DRT = 1
