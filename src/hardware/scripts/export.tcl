if {[version -short] ne "2020.2"} {error "2020.2 required"}
set_param general.maxThreads 2
set root [file normalize [lindex $argv 0]]
set dcp [file normalize [lindex $argv 1]]
set expected [lindex $argv 2]
set hashcmd [format {$s=[IO.File]::OpenRead('%s'); try {([BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($s))).Replace('-','').ToLower()} finally {$s.Dispose()}} $dcp]
set actual [string trim [exec powershell -NoProfile -Command $hashcmd]]
if {$actual ne $expected} {error "Routed DCP SHA256 mismatch"}
open_checkpoint $dcp
if {[get_property PART [current_design]] ne "xc7z020clg400-2"} {error "Part mismatch"}
set n [get_nets -of_objects [get_pins pclk_pad/O]]
if {[llength $n]!=1 || [get_property NAME $n] ne "cam_pclk_ibuf" || [get_property CLOCK_DEDICATED_ROUTE $n] ne "FALSE"} {error "W14 precise exception differs"}
set f [open physical_identity.rpt w]
puts $f "SOURCE_DCP=$dcp SHA256=$actual"
puts $f "W14=[get_property PACKAGE_PIN [get_ports cam_pclk]] ROUTE=[get_property ROUTE $n]"
set iobs [get_cells -hier -filter {NAME =~ pins_reg* && REF_NAME == FDRE}]
if {[llength $iobs]!=10} {error "Expected ten shared DVP IOB registers"}
foreach c $iobs {
 if {![string match ILOGIC* [get_property LOC $c]]} {error "DVP input register not in ILOGIC: $c"}
 puts $f "IOB $c LOC=[get_property LOC $c] IOB=[get_property IOB $c]"
}
foreach c [get_debug_cores] {puts $f [report_property -return_string $c]}
foreach c [get_cells {vio_r8 ila_r8}] {
 puts $f "DEBUG_CLOCK $c [all_fanin -flat -startpoints_only -to [get_pins $c/clk]]"
}
close $f

proc const_pin {pin depth} {
 if {$depth>16} {error "Constant cone too deep"}
 set net [get_nets -of_objects $pin]
 set drivers [get_pins -leaf -of_objects $net -filter {DIRECTION == OUT}]
 set cells [get_cells -of_objects $drivers]
 if {[llength $cells]!=1} {error "Ambiguous constant drivers: $pin $cells"}
 set ref [get_property REF_NAME $cells]
 if {$ref eq "VCC"} {return 1}
 if {$ref eq "GND"} {return 0}
 if {![regexp {^LUT([1-6])$} $ref -> n]} {error "Nonconstant signature cone: $pin $ref"}
 set index 0
 for {set j 0} {$j<$n} {incr j} {
  set v [const_pin [get_pins $cells/I$j] [expr {$depth+1}]]
  set index [expr {$index | ($v << $j)}]
 }
 set init [get_property INIT $cells]
 if {![regexp -nocase {^[0-9]+'h([0-9a-f]+)$} $init -> hex]} {error "Unexpected LUT INIT: $init"}
 set lut [expr "0x$hex"]
 return [expr {($lut >> $index) & 1}]
}
proc const_word {low} {
 set value 0
 for {set i 0} {$i<32} {incr i} {
  set pin [get_pins -quiet [format {vio_r8/probe_in0[%d]} [expr {$low+$i}]]]
  if {[llength $pin]!=1} {error "Expected signature bit pin: $pin"}
  set v [const_pin $pin 0]
  set value [expr {$value | ($v << $i)}]
 }
 return $value
}
set signature [const_word 224]
set buildtag [const_word 192]
set fid [open physical_signature.rpt w]
puts $fid [format {signature=0x%08X build=0x%08X} $signature $buildtag]
close $fid
if {$signature!=0x51554c31 || $buildtag!=0x26110301} {error "Physical signature/build mismatch"}

report_drc -file drc.rpt
report_timing_summary -delay_type min_max -report_unconstrained -check_timing_verbose -file timing_summary.rpt
report_cdc -details -file cdc_raw.rpt
set setup [get_timing_paths -delay_type max -max_paths 1]
set hold [get_timing_paths -delay_type min -max_paths 1]
if {[get_property SLACK $setup]<0 || [get_property SLACK $hold]<0} {error "Final routed timing failed"}
if {[llength [get_drc_violations -quiet -filter {SEVERITY == Error || SEVERITY == {Critical Warning}}]]} {error "Serious DRC prevents export"}
source [file join $root scripts review_fifo_cdc.tcl]
set name Camera_Cartoon_Standalone_QUALITY_01_EXPERIMENTAL
write_debug_probes ${name}.ltx
write_bitstream ${name}.bit
if {[catch {write_hw_platform -fixed -file ${name}.xsa} reason opts]} {
 set f [open xsa_export_error.txt w];puts $f $reason;puts $f [dict get $opts -errorinfo];close $f
 puts "XSA_EXPORT_BLOCKED $reason"
} else {puts "XSA_EXPORT_OK"}
puts "R8_EXPERIMENTAL_EXPORT_OK CONDITIONAL_EXTERNAL_DVP_TIMING"
close_design
