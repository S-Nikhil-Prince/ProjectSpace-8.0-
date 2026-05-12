create_clock -name clk -period 2 -waveform {0 1} [get_ports "clk"]
set_clock_transition -rise 0.1 [get_clocks "clk"]
set_clock_transition -fall 0.1 [get_clocks "clk"]
set_clock_uncertainty 0.001 [get_ports "clk"]

# Input constraints
set_input_transition 0.12 [all_inputs]
set_input_delay -max 0.8 [get_ports "reset"] -clock [get_clocks "clk"]

# Output constraints for DUT outputs
set_output_delay -max 0.5 [all_outputs] -clock [get_clocks "clk"]

# Load and fanout
set_load 0.15 [all_outputs]
set_max_fanout 20.00 [current_design]