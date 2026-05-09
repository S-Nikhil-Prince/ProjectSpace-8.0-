#load libraries
set_db library {/home/install/FOUNDRY/digital/90nm/dig/lib/slow.lib \ /home/install/FOUNDRY/digital/90nm/dig/lib/fast.lib}

#read the design and eloberate
read_hdl -sv Design.sv
elaborate

#read constraints
read_sdc APB_Interface_input_constraints.sdc

#setting effort settings
set_db syn_generic_effort medium
set_db syn_map_effort medium
set_db syn_opt_effort medium

#synthesis flow
syn_generic
syn_map
syn_opt

#generating reports
report_timing > APB_Interface_timing.rep
report_area > APB_Interface_area.rep
report_power > APB_Interface_power.rep

#Outputs
write_hdl > APB_Interface.v
write_sdc > APB_Interface_output_constraints.sdc
report_gates > APB_Interface_counter_gates.v

#GUI
gui_show
