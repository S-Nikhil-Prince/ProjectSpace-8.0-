#load libraries
set lib_dir [expr {[info exists env(FOUNDRY_LIB_DIR)] ? $env(FOUNDRY_LIB_DIR) : "/home/install/FOUNDRY/digital/90nm/dig/lib"}]
set_db library "$lib_dir/slow.lib $lib_dir/fast.lib"

#read the design and eloberate
read_hdl -sv Design.sv

elaborate

#read constraints
read_sdc Hybrid_input_constraints.sdc

#setting effort settings
set_db syn_generic_effort medium
set_db syn_map_effort medium
set_db syn_opt_effort medium

#synthesis flow
syn_generic
syn_map
syn_opt

#generating reports
report_timing > Hybrid_Interface_timing.rep
report_area > Hybrid_Interface_area.rep
report_power > Hybrid_Interface_power.rep

#Outputs
write_hdl > Hybrid_Interface.v
write_sdc > Hybrid_Interface_output_constraints.sdc
report_gates > Hybrid_Interface_gates.v

#GUI
gui_show