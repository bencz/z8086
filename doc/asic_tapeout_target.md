# z8086 tapeout-readiness target

This project stops immediately before commercial foundry submission.  The
implementation must nevertheless be structured so that qualified TSMC 28 nm
HPC libraries and signoff decks can replace the academic placeholders without
changing the architectural behaviour of the CPU.

## Frozen product decisions

- Target process: TSMC 28 nm HPC/HPC+, subject to foundry approval and NDA.
- First chip top: external-memory z8086 with an 8086-style multiplexed bus.
- Second chip top: the same CPU hard macro with 1 MiB of banked on-die SRAM.
- Boot for the SRAM variant: QSPI, with JTAG for debug and manufacturing test.
- Clocking: qualified PLL with external-reference and test-bypass modes.
- Initial package assumption: QFN64; package SI/PI may promote it to BGA.
- Test: full scan, ATPG, boundary scan, SRAM MBIST and PLL bypass.
- Physical organization: timing-driven hierarchy with hard macro boundaries
  and soft/partial standard-cell regions.
- Diagnostics: every warning is fatal; there are no silent waivers.

The current Nangate45 runs remain reproducible architectural experiments.  They
are not foundry signoff and their frequency, area, DRC and IR results are not
claims about TSMC 28 nm silicon.

## Microcode ROM contract

The original microcode is an immutable 512 x 21-bit image.  It is exposed to
the sequencer through `microcode_rom`, a one-cycle synchronous read port
whose output holds when disabled.  `scripts/check_microcode.py` pins the exact
source image by dimensions, encoding and SHA-256 digest.

The generic RTL implementation is used for simulation, FPGA inference and
standard-cell-only experiments.  The production implementation is intended to
be a compiled mask ROM placed next to the microcode sequencer.  Its generated
GDS/OASIS, LEF, Liberty corner models, CDL/SPICE and functional model become
mandatory tapeout inputs.  A gate-ROM implementation remains a benchmark and a
fallback, but may only be selected after post-route timing, power and area are
compared with the mask-ROM macro.

The mask ROM is programmed by its manufactured contact/via pattern.  It is not
loaded at reset, consumes no SRAM capacity, and cannot be modified in the
finished chip.  The external `ucode.hex` file is therefore a build-time source
only; its 10,752 useful bits become permanent geometry in the die.

## Commercial IP boundaries still to be supplied

- TSMC 28 nm standard-cell, I/O, ESD, corner and seal-ring libraries.
- A 512 x 21 (or wider) single-port mask-ROM compiler view set.
- Banked SRAM compiler instances totalling 1 MiB, including MBIST integration.
- PLL, clock I/O and power-on-reset IP.
- Package/bonding rules and the final package model.
- Foundry-qualified extraction, DRC, LVS, ERC, antenna and density decks.

Until those proprietary views are available, open placeholder models must have
identical logical interfaces and must be clearly labelled as non-fabricable.

## Current open-PDK physical milestone

The external-memory chip top now completes synthesis, floorplan, architecture-
seeded placement, CTS, detailed routing, fill, extracted-RC analysis, IR-drop
analysis and GDS merge in the warning-fatal Nangate45 flow.  The reproducible
`padframe_v16_2ns` run has:

- a 1000 x 1000 um die, a site-snapped 319.77 x 313.60 um central
  core-row island, and seven architectural areas occupying 270 x 250 um;
- 48 evenly spaced I/O placement envelopes (12 per side) and four corner
  envelopes;
- a 2.00 ns clock constraint, 1.98 ns extracted minimum-period estimate and
  505.02 MHz estimate at the academic typical corner;
- 14,043 um2 functional standard-cell area at 14% core-row utilization;
- zero final timing/electrical violations, zero detailed-route DRC violations
  and zero antenna violations;
- 368,840 um routed wire, 96,366 vias, 5.91 mW estimated power, 4.06 mV worst
  VDD drop and 3.88 mV worst VSS rise.

`doc/z8086_tapeout_die.png` is a reproducible annotated physical view, not an
LLM illustration or an inferred floorplan diagram. Its large CPU view combines
diffusion, polysilicon, M2-M8 routing and PDN geometry from the final GDS with
functional standard cells coloured at their final ODB coordinates. The inset
is the complete final GDS. Labelled outlines show the architectural placement
areas for the microcode ROM, fetch/decoder, sequencer/control, register bank,
ALU/datapath, shared exchange logic and bus interface. Six are persistent
global-placement guides; shared exchange logic is the centrally seeded movable
population required by RePlAce. Only `FILLCELL` instances are hidden in memory
for legibility; the signed-off files remain unchanged.

The physical merge is dimension-checked after GDS serialization. The flow
fails unless a reread reports the 1000 x 1000 um die and the Nangate45
`DFF_X1` reference cell at 3.46 x 1.63 um. This catches mixed DEF/LEF/GDS
database-unit errors that a visually dense rendering can conceal.

The visible perimeter objects are deliberately non-electrical GDS/placement
envelopes because the academic PDK has no qualified pad, ESD, corner or
seal-ring kit. Consequently, this milestone proves the open physical-flow
structure but is not yet a manufacturable pad ring. Commercial readiness still
requires replacing those envelopes and the gate-mapped microcode ROM with
foundry-qualified physical IP, followed by foundry DRC/LVS/ERC, extraction,
density, EM/IR and multi-corner signoff.
