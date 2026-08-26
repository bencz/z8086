current_design z8086_external_chip_core

set clock_period_ns $::env(Z8086_CLOCK_PERIOD_NS)
set io_delay_ns [expr {$clock_period_ns * 0.20}]
set setup_uncertainty_ns [expr {$clock_period_ns * 0.05}]
set hold_uncertainty_ns [expr {$clock_period_ns * 0.0025}]

create_clock -name core_clock -period $clock_period_ns [get_ports clk]
set_clock_uncertainty -setup $setup_uncertainty_ns [get_clocks core_clock]
set_clock_uncertainty -hold $hold_uncertainty_ns [get_clocks core_clock]
set_input_delay $io_delay_ns -clock core_clock [all_inputs -no_clocks]
set_output_delay $io_delay_ns -clock core_clock [all_outputs]
set_input_transition 0.10 [all_inputs -no_clocks]
set_load 5.0 [all_outputs]
set_max_fanout 64 [current_design]
