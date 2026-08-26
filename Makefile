SHELL := /usr/bin/env bash

BUILD_DIR ?= $(abspath build)
FLOW_VARIANT ?= baseline

.DEFAULT_GOAL := help

help:
	@echo "z8086 development targets"
	@echo "  make test                 run the existing CPU regression"
	@echo "  make microcode-check      verify the bit-exact original microcode ROM"
	@echo "  make sim-soc              run the interactive Snake SoC simulation"
	@echo "  make asic-external-synth  synthesize the external-memory variant"
	@echo "  make asic-external-finish run its complete physical flow"
	@echo "  make asic-external-render render its physical-stage PNGs"
	@echo "  make asic-tapeout-finish  build the pad-limited external chip GDS"
	@echo "  make asic-tapeout-render  render the complete external chip"
	@echo "  make asic-tapeout-die-photo capture the external chip directly from GDS"
	@echo "  make asic-synth           synthesize the 1 MiB on-die-SRAM variant"
	@echo "  make asic-floorplan       create its macro-aware floorplan"
	@echo "  make asic-place           run global and detailed placement"
	@echo "  make asic-cts             build the clock tree"
	@echo "  make asic-route           route and extract the chip"
	@echo "  make asic-finish          sign off the on-die variant (ODB/DEF/SPEF)"
	@echo "  make asic-render          render physical-stage PNGs"
	@echo "  make asic-die-photo       capture the logic-only die directly from GDS"

microcode-check:
	python3 scripts/check_microcode.py

asic-placeholder-ip:
	scripts/asic/generate_placeholder_io.sh

test: microcode-check
	CCACHE_DISABLE=1 $(MAKE) -C tests build
	@if [[ -d tests/8088 ]]; then \
		cd tests && python3 test8088.py; \
	else \
		echo "SKIP: optional tests/8088 vectors are not installed"; \
	fi
	cd tests && python3 test186.py
	CCACHE_DISABLE=1 $(MAKE) -C tests sim-int
	CCACHE_DISABLE=1 $(MAKE) -C tests sim-bus
	CCACHE_DISABLE=1 $(MAKE) -C tests sim-asic-ram
	CCACHE_DISABLE=1 $(MAKE) -C tests sim-external-chip
	CCACHE_DISABLE=1 $(MAKE) -C tests sim-soc-headless

sim-soc:
	$(MAKE) -C tests sim-soc

asic-external-synth asic-external-floorplan asic-external-place \
asic-external-cts asic-external-route asic-external-finish:
	BUILD_DIR="$(BUILD_DIR)/asic-nangate45-external" FLOW_VARIANT="$(FLOW_VARIANT)" \
		ASIC_DESIGN=core scripts/asic/run_nangate45.sh "$(subst asic-external-,,$@)"

asic-core-synth: asic-external-synth

asic-external-synth asic-synth: microcode-check

asic-tapeout-synth asic-tapeout-floorplan asic-tapeout-place \
asic-tapeout-cts asic-tapeout-route asic-tapeout-finish: microcode-check asic-placeholder-ip
	BUILD_DIR="$(BUILD_DIR)/asic-nangate45-external-chip" FLOW_VARIANT="$(FLOW_VARIANT)" \
		ASIC_DESIGN=external_chip scripts/asic/run_nangate45.sh "$(subst asic-tapeout-,,$@)"

asic-synth asic-floorplan asic-place asic-cts asic-route asic-finish:
	BUILD_DIR="$(BUILD_DIR)/asic-nangate45" FLOW_VARIANT="$(FLOW_VARIANT)" \
		ASIC_DESIGN=chip scripts/asic/run_nangate45.sh "$(@:asic-%=%)"

asic-render:
	BUILD_DIR="$(BUILD_DIR)/asic-nangate45" FLOW_VARIANT="$(FLOW_VARIANT)" \
		ASIC_DESIGN=chip scripts/asic/render_nangate45.sh

asic-external-render:
	BUILD_DIR="$(BUILD_DIR)/asic-nangate45-external" FLOW_VARIANT="$(FLOW_VARIANT)" \
		ASIC_DESIGN=core scripts/asic/render_nangate45.sh

asic-tapeout-render:
	BUILD_DIR="$(BUILD_DIR)/asic-nangate45-external-chip" FLOW_VARIANT="$(FLOW_VARIANT)" \
		ASIC_DESIGN=external_chip scripts/asic/render_nangate45.sh

asic-die-photo:
	scripts/asic/render_die_photo.sh

asic-tapeout-die-photo:
	ASIC_DESIGN=external_chip scripts/asic/render_die_photo.sh

asic-die-image: asic-die-photo

.PHONY: help test microcode-check asic-placeholder-ip sim-soc asic-core-synth asic-external-synth \
	asic-external-floorplan asic-external-place asic-external-cts \
	asic-external-route asic-external-finish asic-external-render \
	asic-tapeout-synth asic-tapeout-floorplan asic-tapeout-place \
	asic-tapeout-cts asic-tapeout-route asic-tapeout-finish asic-tapeout-render \
	asic-tapeout-die-photo \
	asic-synth asic-floorplan asic-place asic-cts asic-route asic-finish \
	asic-render asic-die-photo asic-die-image
