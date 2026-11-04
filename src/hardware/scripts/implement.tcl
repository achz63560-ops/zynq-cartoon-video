# Fresh complete offline project, with all IP generated into this run.
source [file join [file dirname [info script]] prepare.tcl]
open_project [file join $out p r8.xpr]
set_property synth_checkpoint_mode None [get_files backend.bd]
add_files -norecurse [glob [file join $out p r8.gen sources_1 bd backend hdl backend_wrapper.v]]
file copy [file join $local_inputs reference sequence.mem] [file join $out sequence.mem]
add_files -norecurse [file join $out sequence.mem]
read_verilog -sv [glob [file join $root rtl *.sv]]
read_verilog -sv [glob [file join $root rtl *.v]]
foreach module {dvi_encoder.v dvi_tx_serial.v serializer_10_to_1.v} {
 read_verilog -sv [file join $local_inputs rtl $module]
}
read_xdc [file join $root constraints pins.xdc]
read_xdc [file join $root constraints timing.xdc]
set_property top camera_hdmi_top [current_fileset]
update_compile_order -fileset sources_1
# Short reset shift chains must remain FFs: b04's SRL3->same-slice FF has
# zero routing delay and fails the retained 1 ns PCLK hold uncertainty.
synth_design -top camera_hdmi_top -part xc7z020clg400-2 -shreg_min_size 5
set n [get_nets -of_objects [get_pins pclk_pad/O]]
if {[llength $n]!=1 || [get_property NAME $n] ne "cam_pclk_ibuf"} {error "Unexpected W14 exception target"}
set_property CLOCK_DEDICATED_ROUTE FALSE $n
report_property $n -file exact_pclk_exception.rpt
set first [get_cells -hier -regexp {.*(scl_meta_reg|sda_meta_reg|sda_a_reg|nc_meta_reg)$}]
if {[llength $first]!=4} {error "Expected exact four single-bit pin synchronizer first stages, got $first"}
foreach c $first {if {[get_property ASYNC_REG $c] ni {1 TRUE}} {error "Pin first-stage not ASYNC_REG: $c"}}
set_false_path -from [get_ports {cam_scl cam_sda cam_xclk_nc}] -to [get_pins -of_objects $first -filter {REF_PIN_NAME == D}]
set hub [get_debug_cores -quiet dbg_hub]
if {[llength $hub]!=1} {error "SYS debug hub missing"}
set_property C_CLK_INPUT_FREQ_HZ 50000000 $hub
disconnect_debug_port dbg_hub/clk
connect_debug_port dbg_hub/clk [get_nets -of_objects [get_pins sys_global/O]]
set keyff [get_cells -hier -filter {NAME == local_control/key/key_meta_reg}]
if {[llength $keyff]!=1 || [get_property ASYNC_REG $keyff] ni {1 TRUE}} {error "Exact key input synchronizer missing"}
# Asynchronous mechanical single-bit input: only the first synchronizer D pin.
set_false_path -from [get_ports mode_key_n] -to [get_pins -of_objects $keyff -filter {REF_PIN_NAME == D}]
write_checkpoint synthesized.dcp
report_utilization -file synth_utilization.rpt
report_cdc -details -file synth_cdc.rpt
opt_design
place_design
phys_opt_design
route_design
write_checkpoint routed.dcp
report_route_status -file route.rpt
report_utilization -file utilization.rpt
report_io -file io.rpt
report_clocks -file clocks.rpt
report_clock_utilization -file clock_utilization.rpt
report_timing_summary -delay_type min_max -report_unconstrained -check_timing_verbose -file timing_summary.rpt
report_timing -delay_type min -max_paths 30 -path_type full_clock_expanded -file hold.rpt
report_timing -from [get_ports {cam_data[*] cam_href cam_vsync}] -delay_type min -max_paths 12 -path_type full_clock_expanded -file dvp_hold.rpt
report_timing -from [get_ports {cam_data[*] cam_href cam_vsync}] -delay_type max -max_paths 12 -path_type full_clock_expanded -file dvp_setup.rpt
report_cdc -details -file cdc.rpt
report_drc -file drc.rpt
report_exceptions -coverage -file exceptions.rpt
check_timing -verbose -file check_timing.rpt
report_bus_skew -delay_type min_max -file bus_skew.rpt
set ff [open fifo36_reset_review.rpt w]
foreach c [get_cells -hier -filter {REF_NAME == FIFO36E1}] {
 puts $ff [report_property -return_string $c]
 foreach pn {RST RDCLK WRCLK RDEN WREN} {
  set pin [get_pins $c/$pn]
  puts $ff "PIN $pin NET [get_nets -of_objects $pin]"
  puts $ff "STARTPOINTS [all_fanin -flat -startpoints_only -to $pin]"
 }
}
close $ff
help write_verilog
set f [open route_detail.rpt w]
foreach net {cam_pclk_ibuf cam_g} {puts $f "$net ROUTE=[get_property ROUTE [get_nets $net]]"}
foreach dc [get_debug_cores] {puts $f "CORE $dc [report_property -return_string $dc]"}
close $f
set setup [get_timing_paths -delay_type max -max_paths 1]
set hold [get_timing_paths -delay_type min -max_paths 1]
set f [open timing_result.txt w];puts $f "WNS=[get_property SLACK $setup] WHS=[get_property SLACK $hold]";close $f
if {[llength [get_drc_violations -quiet -filter {SEVERITY == Error || SEVERITY == {Critical Warning}}]]} {error "Serious DRC; no image"}
if {[get_property SLACK $setup]<0 || [get_property SLACK $hold]<0} {error "Full top timing failed; no image"}
file copy cdc.rpt cdc_raw.rpt
source [file join $root scripts review_fifo_cdc.tcl]
set f [open cdc_reviewed.rpt];set cdc [read $f];close $f
if {[regexp -line -nocase {^CDC-[0-9]+[ \t]+(Critical|Warning)[ \t]+[1-9]} $cdc]} {error "CDC unresolved; no image"}
# Export is a separate final step after functional and constraint reviews.
# Successful route alone does not create a downloadable candidate.
# 2020.2 requires reopening the saved checkpoint for native HSI export when
# this project was implemented through direct synth/place/route Tcl commands.
puts "R10_ROUTED_OFFLINE_EXPORT_FROM_SAVED_DCP_PENDING"
close_project
