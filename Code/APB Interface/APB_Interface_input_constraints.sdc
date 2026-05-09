create_clock -name clk -period 2 -waveform {0 1} [get_ports *clk*]
set_clock_transition -rise 0.1 [get_clocks clk]
set_clock_transition -fall 0.1 [get_clocks clk]
set_clock_uncertainty 0.001 [get_clocks clk]

set_input_transition 0.12 [all_inputs]

# Apply input delay to all inputs except the clock
set_input_delay -max 0.8 -clock [get_clocks clk] [remove_from_collection [all_inputs] [get_ports *clk*]]

# Apply output delay to all outputs
set_output_delay -max 0.8 -clock [get_clocks clk] [all_outputs]

set_load 0.15 [all_outputs]
set_max_fanout 20.00 [current_design]
