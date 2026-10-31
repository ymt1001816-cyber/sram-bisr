# constraint.sdc : one clock, 200 MHz (OpenSTA)
set clk_port [get_ports clk]
create_clock -name clk -period 5.0 $clk_port
set non_clk_inputs [lsearch -inline -all -not -exact [all_inputs] $clk_port]
set_input_delay  0.5 -clock clk $non_clk_inputs
set_output_delay 0.5 -clock clk [all_outputs]
