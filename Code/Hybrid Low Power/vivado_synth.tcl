# ============================================================
# Vivado FPGA Synthesis Script
# ============================================================
# Target: Xilinx Artix-7 (xc7a35tcpg236-1)
# Purpose: FPGA prototyping of AXI-APB Hybrid Interface
#
# Usage:
#   vivado -mode batch -source vivado_synth.tcl
#
# Note: Primary synthesis uses Cadence Genus (ASIC flow).
#       This script provides an alternative FPGA implementation
#       path for rapid prototyping and functional validation.
# ============================================================

# Create project
create_project hybrid_fpga ./vivado_project -part xc7a35tcpg236-1 -force

# Add design sources (synthesis only — TB is not synthesizable)
add_files -fileset sources_1 Design.sv

# Add constraints
add_files -fileset constrs_1 fpga_constraints.xdc

# Set top module
set_property top top_memory_system [current_fileset]

# Run synthesis
launch_runs synth_1 -jobs 4
wait_on_run synth_1

# Report utilization and timing
open_run synth_1
report_utilization -file fpga_utilization.rep
report_timing_summary -file fpga_timing.rep
report_power -file fpga_power.rep

# Optional: Run implementation
# launch_runs impl_1 -jobs 4
# wait_on_run impl_1

puts "FPGA synthesis complete. Reports generated."
