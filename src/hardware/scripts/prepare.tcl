if {$argc != 2} {error "Usage: prepare.tcl <hardware_source_root> <authorized_board_inputs_root>"}
set root [file normalize [lindex $argv 0]]
set local_inputs [file normalize [lindex $argv 1]]
set out [pwd]
if {[version -short] ne "2020.2"} {error "2020.2 required"}
set_param general.maxThreads 2
create_project r8 [file join $out p] -part xc7z020clg400-2
set_property target_language Verilog [current_project]
set_property XPM_LIBRARIES {XPM_CDC} [current_project]
# Only the physically instantiated depth. Depth 32 belongs to old small tests.
foreach depth {1024} {
 create_ip -name fifo_generator -vendor xilinx.com -library ip -version 13.2 -module_name camera_async_fifo_$depth
 set_property -dict [list CONFIG.Fifo_Implementation {Independent_Clocks_Block_RAM} CONFIG.Input_Data_Width 19 CONFIG.Input_Depth $depth CONFIG.Output_Data_Width 19 CONFIG.Output_Depth $depth CONFIG.Performance_Options {First_Word_Fall_Through} CONFIG.Reset_Type {Asynchronous_Reset} CONFIG.Overflow_Flag true CONFIG.Underflow_Flag true] [get_ips camera_async_fifo_$depth]
 set_property GENERATE_SYNTH_CHECKPOINT false [get_files camera_async_fifo_$depth.xci]
}
create_ip -name vio -vendor xilinx.com -library ip -version 3.0 -module_name integration_vio
set cfg [list CONFIG.C_NUM_PROBE_IN 8 CONFIG.C_NUM_PROBE_OUT 9 CONFIG.C_PROBE_IN0_WIDTH 256 CONFIG.C_PROBE_IN1_WIDTH 256 CONFIG.C_PROBE_IN2_WIDTH 256 CONFIG.C_PROBE_IN3_WIDTH 128 CONFIG.C_PROBE_IN4_WIDTH 128 CONFIG.C_PROBE_IN5_WIDTH 256 CONFIG.C_PROBE_IN6_WIDTH 256 CONFIG.C_PROBE_IN7_WIDTH 128 CONFIG.C_PROBE_OUT8_WIDTH 3 CONFIG.C_PROBE_OUT8_INIT_VAL 0]
for {set i 0} {$i<8} {incr i} {lappend cfg CONFIG.C_PROBE_OUT${i}_WIDTH 1 CONFIG.C_PROBE_OUT${i}_INIT_VAL 0}
set_property -dict $cfg [get_ips integration_vio]
set_property GENERATE_SYNTH_CHECKPOINT false [get_files integration_vio.xci]
create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name integration_ila
set_property -dict {CONFIG.C_NUM_OF_PROBES 1 CONFIG.C_PROBE0_WIDTH 128 CONFIG.C_DATA_DEPTH 1024 CONFIG.C_INPUT_PIPE_STAGES 0} [get_ips integration_ila]
set_property GENERATE_SYNTH_CHECKPOINT false [get_files integration_ila.xci]
generate_target all [get_ips]

create_bd_design backend
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 ps
source [file join $local_inputs reference ps_board_config.tcl]
set_property -dict {CONFIG.PCW_USE_S_AXI_HP0 1 CONFIG.PCW_S_AXI_HP0_DATA_WIDTH 64 CONFIG.PCW_USE_M_AXI_GP0 1 CONFIG.PCW_EN_CLK0_PORT 1 CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ 100} [get_bd_cells ps]
foreach p {DDR FIXED_IO} {
 make_bd_intf_pins_external [get_bd_intf_pins ps/$p]
 set_property name $p [get_bd_intf_ports ${p}_0]
}
create_bd_port -dir I -type clk sys_clk
set_property CONFIG.FREQ_HZ 50000000 [get_bd_ports sys_clk]
create_bd_port -dir I -type clk pix_clk
set_property CONFIG.FREQ_HZ 74250000 [get_bd_ports pix_clk]
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 one
set_property CONFIG.CONST_VAL 1 [get_bd_cells one]
foreach n {sys mem} {
 create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 reset_$n
 # Derived from the PS FCLK_RESET0_N ACTIVE_LOW interface, not a writable BD parameter.
 connect_bd_net [get_bd_pins ps/FCLK_RESET0_N] [get_bd_pins reset_$n/ext_reset_in]
 connect_bd_net [get_bd_pins one/dout] [get_bd_pins reset_$n/dcm_locked]
}
connect_bd_net [get_bd_ports sys_clk] [get_bd_pins reset_sys/slowest_sync_clk]
connect_bd_net [get_bd_pins ps/FCLK_CLK0] [get_bd_pins reset_mem/slowest_sync_clk]
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 ready_gpio
set_property -dict {CONFIG.C_GPIO_WIDTH 32 CONFIG.C_ALL_OUTPUTS 1 CONFIG.C_DOUT_DEFAULT 0x00000000 CONFIG.C_IS_DUAL 1 CONFIG.C_GPIO2_WIDTH 32 CONFIG.C_ALL_INPUTS_2 1} [get_bd_cells ready_gpio]
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 ps_control
set_property -dict {CONFIG.NUM_SI 1 CONFIG.NUM_MI 1} [get_bd_cells ps_control]
connect_bd_intf_net [get_bd_intf_pins ps/M_AXI_GP0] [get_bd_intf_pins ps_control/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins ps_control/M00_AXI] [get_bd_intf_pins ready_gpio/S_AXI]
connect_bd_net [get_bd_pins ps/FCLK_CLK0] [get_bd_pins ps/M_AXI_GP0_ACLK] [get_bd_pins ps_control/ACLK] [get_bd_pins ps_control/S00_ACLK]
connect_bd_net [get_bd_ports sys_clk] [get_bd_pins ps_control/M00_ACLK] [get_bd_pins ready_gpio/s_axi_aclk]
connect_bd_net [get_bd_pins reset_mem/peripheral_aresetn] [get_bd_pins ps_control/ARESETN] [get_bd_pins ps_control/S00_ARESETN]
connect_bd_net [get_bd_pins reset_sys/peripheral_aresetn] [get_bd_pins ps_control/M00_ARESETN] [get_bd_pins ready_gpio/s_axi_aresetn]
make_bd_pins_external [get_bd_pins ready_gpio/gpio_io_o]
set_property name ps_control [get_bd_ports gpio_io_o_0]
make_bd_pins_external [get_bd_pins ready_gpio/gpio2_io_i]
set_property name ps_status [get_bd_ports gpio2_io_i_0]

create_bd_cell -type ip -vlnv xilinx.com:ip:axi_vdma:6.3 dma
set_property -dict [list CONFIG.c_include_sg 0 CONFIG.c_num_fstores 2 CONFIG.c_include_mm2s 1 CONFIG.c_include_s2mm 1 CONFIG.c_m_axi_mm2s_data_width 64 CONFIG.c_m_axi_s2mm_data_width 64 CONFIG.c_m_axis_mm2s_tdata_width 24 CONFIG.c_use_fsync 0 CONFIG.c_use_mm2s_fsync 0 CONFIG.c_use_s2mm_fsync 0 CONFIG.c_include_internal_genlock 0 CONFIG.c_mm2s_genlock_mode 0 CONFIG.c_s2mm_genlock_mode 0 CONFIG.c_include_s2mm_sf 1 CONFIG.c_include_mm2s_dre 0 CONFIG.c_include_s2mm_dre 0 CONFIG.c_mm2s_linebuffer_depth 512 CONFIG.c_s2mm_linebuffer_depth 512 CONFIG.c_mm2s_max_burst_length 8 CONFIG.c_s2mm_max_burst_length 8 CONFIG.c_enable_s2mm_rst_out 1 CONFIG.c_enable_mm2s_rst_out 1] [get_bd_cells dma]
foreach pair {{S_AXI_LITE VDMA_CTRL} {S_AXIS_S2MM CAMERA_AXIS} {M_AXIS_MM2S DISPLAY_AXIS}} {
 lassign $pair pin port
 make_bd_intf_pins_external [get_bd_intf_pins dma/$pin]
 set_property name $port [get_bd_intf_ports ${pin}_0]
}
# S2MM width is propagated from the actual AXIS source interface in BD.
set_property -dict {CONFIG.TDATA_NUM_BYTES 3 CONFIG.HAS_TKEEP 1 CONFIG.HAS_TLAST 1 CONFIG.TUSER_WIDTH 1} [get_bd_intf_ports CAMERA_AXIS]
set_property CONFIG.ASSOCIATED_BUSIF {VDMA_CTRL:CAMERA_AXIS} [get_bd_ports sys_clk]
set_property CONFIG.ASSOCIATED_BUSIF {DISPLAY_AXIS} [get_bd_ports pix_clk]
connect_bd_net [get_bd_ports sys_clk] [get_bd_pins dma/s_axi_lite_aclk] [get_bd_pins dma/s_axis_s2mm_aclk]
connect_bd_net [get_bd_ports pix_clk] [get_bd_pins dma/m_axis_mm2s_aclk]
connect_bd_net [get_bd_pins ps/FCLK_CLK0] [get_bd_pins dma/m_axi_s2mm_aclk] [get_bd_pins dma/m_axi_mm2s_aclk]
connect_bd_net [get_bd_pins reset_sys/peripheral_aresetn] [get_bd_pins dma/axi_resetn]
foreach pin {s2mm_prmry_reset_out_n mm2s_prmry_reset_out_n} {
 make_bd_pins_external [get_bd_pins dma/$pin]
 set_property name $pin [get_bd_ports ${pin}_0]
}
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 memory
set_property -dict {CONFIG.NUM_SI 2 CONFIG.NUM_MI 1} [get_bd_cells memory]
connect_bd_intf_net [get_bd_intf_pins dma/M_AXI_MM2S] [get_bd_intf_pins memory/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins dma/M_AXI_S2MM] [get_bd_intf_pins memory/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins memory/M00_AXI] [get_bd_intf_pins ps/S_AXI_HP0]
connect_bd_net [get_bd_pins ps/FCLK_CLK0] [get_bd_pins memory/ACLK] [get_bd_pins memory/S00_ACLK] [get_bd_pins memory/S01_ACLK] [get_bd_pins memory/M00_ACLK] [get_bd_pins ps/S_AXI_HP0_ACLK]
connect_bd_net [get_bd_pins reset_mem/peripheral_aresetn] [get_bd_pins memory/ARESETN] [get_bd_pins memory/S00_ARESETN] [get_bd_pins memory/S01_ARESETN] [get_bd_pins memory/M00_ARESETN]
assign_bd_address
set_property offset 0x41200000 [get_bd_addr_segs ps/Data/SEG_ready_gpio_Reg]
validate_bd_design
if {[get_property CONFIG.c_s_axis_s2mm_tdata_width [get_bd_cells dma]]!=24} {error "S2MM must be 24-bit RGB888"}
foreach n {sys mem} {if {[get_property CONFIG.C_EXT_RESET_HIGH [get_bd_cells reset_$n]]!=0} {error "Reset polarity did not propagate"}}
save_bd_design
report_property [get_bd_cells ps] -file ps_properties.rpt
report_property [get_bd_cells dma] -file vdma_properties.rpt
write_bd_tcl [file join $out backend_recreate.tcl]
generate_target all [get_files backend.bd]
make_wrapper -files [get_files backend.bd] -top
report_ip_status -file ip_status.rpt
puts "R8_BACKEND_PREPARED_NO_HARDWARE"
close_project
