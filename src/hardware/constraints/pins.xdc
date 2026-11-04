set_property PACKAGE_PIN U18 [get_ports sys_clk]
set_property PACKAGE_PIN W14 [get_ports cam_pclk]
set_property PACKAGE_PIN U12 [get_ports cam_vsync]
set_property PACKAGE_PIN T12 [get_ports cam_href]
set_property PACKAGE_PIN W15 [get_ports cam_xclk_nc]
set_property PACKAGE_PIN T10 [get_ports cam_scl]
set_property PACKAGE_PIN T11 [get_ports cam_sda]
set_property PACKAGE_PIN P14 [get_ports cam_reset_n]
set_property PACKAGE_PIN V15 [get_ports cam_pwdn]
set_property PACKAGE_PIN R14 [get_ports {cam_data[0]}]
set_property PACKAGE_PIN U13 [get_ports {cam_data[1]}]
set_property PACKAGE_PIN V13 [get_ports {cam_data[2]}]
set_property PACKAGE_PIN U15 [get_ports {cam_data[3]}]
set_property PACKAGE_PIN U14 [get_ports {cam_data[4]}]
set_property PACKAGE_PIN W13 [get_ports {cam_data[5]}]
set_property PACKAGE_PIN V12 [get_ports {cam_data[6]}]
set_property PACKAGE_PIN Y14 [get_ports {cam_data[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sys_clk cam_*}]
set_property PULLUP false [get_ports {sys_clk cam_*}]
set_property PULLDOWN false [get_ports {sys_clk cam_*}]
set_property DRIVE 4 [get_ports {cam_scl cam_sda cam_reset_n cam_pwdn}]
set_property SLEW SLOW [get_ports {cam_scl cam_sda cam_reset_n cam_pwdn}]
set_property BITSTREAM.CONFIG.UNUSEDPIN Pullnone [current_design]

# ALIENTEK Navigator ZYNQ XC7Z020 HDMI color-bar experiment.
# Board-specific pins: FPGA Guide V3.4, Chapter 31, table 31.5.1 (PDF p.768).
# DO NOT reuse this constraint file on another carrier board.

# PL 50 MHz oscillator and active-low reset button.
# The 20 ns input clock is defined by the Clocking Wizard's generated XDC.

# TMDS data channel 2: red.
set_property PACKAGE_PIN J20 [get_ports {tmds_data_p[2]}]
set_property PACKAGE_PIN H20 [get_ports {tmds_data_n[2]}]
set_property IOSTANDARD TMDS_33 [get_ports {tmds_data_p[2]}]

# TMDS data channel 1: green.
set_property PACKAGE_PIN K19 [get_ports {tmds_data_p[1]}]
set_property PACKAGE_PIN J19 [get_ports {tmds_data_n[1]}]
set_property IOSTANDARD TMDS_33 [get_ports {tmds_data_p[1]}]

# TMDS data channel 0: blue / sync controls.
set_property PACKAGE_PIN G19 [get_ports {tmds_data_p[0]}]
set_property PACKAGE_PIN G20 [get_ports {tmds_data_n[0]}]
set_property IOSTANDARD TMDS_33 [get_ports {tmds_data_p[0]}]

# TMDS reference clock.
set_property PACKAGE_PIN J18 [get_ports tmds_clk_p]
set_property PACKAGE_PIN H18 [get_ports tmds_clk_n]
set_property IOSTANDARD TMDS_33 [get_ports tmds_clk_p]

# Official Vitis Guide V1.2 PDF p99; carrier schematic p1 R6=10K to 3.3V.
set_property PACKAGE_PIN L14 [get_ports mode_key_n]
set_property IOSTANDARD LVCMOS33 [get_ports mode_key_n]
