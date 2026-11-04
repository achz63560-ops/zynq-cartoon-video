# CONDITIONAL MODEL ONLY. These values are NOT OV5640 guaranteed bounds.
create_clock -name sys_clk -period 20.000 [get_ports sys_clk]
create_clock -name camera_pclk -period 83.333 -waveform {0.000 41.6665} [get_ports cam_pclk]
set_clock_uncertainty 1.000 [get_clocks camera_pclk]
set_input_delay -clock camera_pclk -clock_fall -min -1.000 [get_ports {cam_data[*] cam_href cam_vsync}]
set_input_delay -clock camera_pclk -clock_fall -max 10.000 [get_ports {cam_data[*] cam_href cam_vsync}]
# Asynchronous SCCB/reset controls are physical path budgets, not fake DVP I/O.
set_max_delay -datapath_only 100.000 -from [get_clocks sys_clk] -to [get_ports {cam_scl cam_sda cam_reset_n cam_pwdn}]
