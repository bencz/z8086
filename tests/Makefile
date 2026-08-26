TOP      ?= tb_z8086
VERILATOR ?= verilator

SRC_V = \
  ../src/z8086/microcode_rom.sv \
  ../src/z8086/z8086.sv \
  ../src/soc/spram.sv \
  ../src/z8086/alu.sv \
  tb_z8086.sv

SRC_V_INT = \
  ../src/z8086/microcode_rom.sv \
  ../src/z8086/z8086.sv \
  ../src/z8086/alu.sv \
  tb_interrupt_test.sv

SRC_V_SOC = \
  ../src/z8086/microcode_rom.sv \
  ../src/z8086/z8086.sv \
  ../src/z8086/alu.sv \
  tb_soc_headless.sv

SRC_CPP_SOC = soc_terminal.cpp

SRC_V_ASIC_RAM = \
  fakeram45_1024x32.sv \
  ../config/asic/nangate45/z8086_onchip_ram.sv \
  tb_onchip_ram.sv

SRC_V_EXTERNAL_CHIP = \
  ../src/z8086/microcode_rom.sv \
  ../src/z8086/z8086.sv \
  ../src/z8086/alu.sv \
  ../src/asic/z8086_bus8086_bridge.sv \
  ../src/asic/z8086_external_chip_core.sv \
  ../src/asic/z8086_external_chip.sv \
  tb_external_chip.sv

all: sim

build: obj_dir/V$(TOP)

sim: obj_dir/V$(TOP)
	./obj_dir/V$(TOP)

obj_dir/V$(TOP): $(SRC_V) sim_main.cpp ../src/z8086/ucode.hex
	$(VERILATOR) -cc --exe +incdir+../src --build -Wall -Wno-PINCONNECTEMPTY --timing --top-module $(TOP) \
	  -Wno-IMPLICITSTATIC -Wno-TIMESCALEMOD -Wno-UNDRIVEN -Wno-UNUSEDSIGNAL -Wno-WIDTHEXPAND -Wno-VARHIDDEN -Wno-PROCASSINIT -Wno-CASEINCOMPLETE \
	  --trace-fst -sv $(SRC_V) sim_main.cpp --error-limit 0
	cp ../src/z8086/ucode.hex .

# Interrupt test targets
build-int: obj_dir/Vtb_interrupt_test

sim-int: obj_dir/Vtb_interrupt_test
	./obj_dir/Vtb_interrupt_test +trace

obj_dir/Vtb_interrupt_test: $(SRC_V_INT)
	$(VERILATOR) --binary --timing --top-module tb_interrupt_test -Wno-fatal \
	  -Wno-TIMESCALEMOD -Wno-UNDRIVEN -Wno-UNUSEDSIGNAL -Wno-WIDTHEXPAND -Wno-VARHIDDEN -Wno-PROCASSINIT -Wno-CASEINCOMPLETE \
	  --trace-fst -sv $(SRC_V_INT)

# Headless HDMI-demo/firmware simulation (scripted UART + text VRAM dump)
build-soc: obj_dir/Vtb_soc_headless

sim-soc: obj_dir/Vtb_soc_headless
	./obj_dir/Vtb_soc_headless +interactive=1 +command=snake +keys=x

sim-soc-headless: obj_dir/Vtb_soc_headless
	./obj_dir/Vtb_soc_headless +command=snake +keys=x

obj_dir/Vtb_soc_headless: $(SRC_V_SOC) $(SRC_CPP_SOC) ../src/z8086/ucode.hex ../src/soc_hdmi/soc_hdmi.hex
	$(VERILATOR) --binary --timing --top-module tb_soc_headless -Wno-fatal \
	  -Wno-TIMESCALEMOD -Wno-UNDRIVEN -Wno-UNUSEDSIGNAL -Wno-WIDTHEXPAND -Wno-VARHIDDEN -Wno-PROCASSINIT -Wno-CASEINCOMPLETE \
	  --trace-fst -sv $(SRC_V_SOC) $(SRC_CPP_SOC)
	cp ../src/z8086/ucode.hex .

sim-bus: obj_dir/V$(TOP)
	./obj_dir/V$(TOP) +io_split_test=1 +cycles=5000

sim-asic-ram: obj_dir/Vtb_onchip_ram
	./obj_dir/Vtb_onchip_ram

sim-external-chip: obj_dir/Vtb_external_chip
	./obj_dir/Vtb_external_chip

obj_dir/Vtb_onchip_ram: $(SRC_V_ASIC_RAM)
	$(VERILATOR) --binary --timing --top-module tb_onchip_ram \
	  -Wall -DZ8086_EXTERNAL_FAKERAM_MODEL -sv $(SRC_V_ASIC_RAM)

obj_dir/Vtb_external_chip: $(SRC_V_EXTERNAL_CHIP) ../src/z8086/ucode.hex
	$(VERILATOR) --binary --timing --top-module tb_external_chip \
	  -Wall -Wno-TIMESCALEMOD -Wno-UNUSEDSIGNAL -Wno-PROCASSINIT \
	  -Wno-CASEINCOMPLETE -sv $(SRC_V_EXTERNAL_CHIP)
	cp ../src/z8086/ucode.hex .

clean:
	rm -rf obj_dir *.vcd *.fst ucode.hex

.PHONY: all sim clean build build-int sim-int build-soc sim-soc sim-soc-headless \
	sim-bus sim-asic-ram sim-external-chip
