## ============================================================
## Vivado FPGA Synthesis Constraints (Artix-7 Target)
## ============================================================
## Target Device: xc7a35tcpg236-1 (Artix-7)
## Purpose: FPGA prototyping of the AXI-APB Hybrid Interface
## Primary synthesis flow uses Cadence Genus (ASIC);
## this XDC enables optional FPGA validation on Xilinx Artix-7.
## ============================================================

# Clock Definition (100 MHz)
create_clock -period 10.000 -name sys_clk -waveform {0.000 5.000} [get_ports clk]
set_property CLOCK_DEDICATED_ROUTE TRUE [get_nets clk]

# Input Delays
set_input_delay -clock sys_clk -max 3.0 [get_ports reset]
set_input_delay -clock sys_clk -max 3.0 [get_ports {addr[*]}]
set_input_delay -clock sys_clk -max 3.0 [get_ports {wdata[*]}]
set_input_delay -clock sys_clk -max 3.0 [get_ports write]
set_input_delay -clock sys_clk -max 3.0 [get_ports read]
set_input_delay -clock sys_clk -max 3.0 [get_ports burst_hint]

# Output Delays
set_output_delay -clock sys_clk -max 2.0 [get_ports {rdata[*]}]
set_output_delay -clock sys_clk -max 2.0 [get_ports use_axi]
set_output_delay -clock sys_clk -max 2.0 [get_ports use_apb]

# FPGA Pin Assignments (Artix-7 xc7a35tcpg236-1)
set_property PACKAGE_PIN W5  [get_ports clk]
set_property PACKAGE_PIN U18 [get_ports reset]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports reset]
set_property IOSTANDARD LVCMOS33 [get_ports {rdata[*]}]
set_property IOSTANDARD LVCMOS33 [get_ports use_axi]
set_property IOSTANDARD LVCMOS33 [get_ports use_apb]
