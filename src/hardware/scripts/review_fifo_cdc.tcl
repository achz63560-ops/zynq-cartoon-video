# Only the two documented 7-series asynchronous FIFO primitive reset paths.
# No timing exception or DRC severity is changed by this review.
# Evidence: docs/CDC与时序修复记录.md, b05/fifo36_reset_review.rpt,
# and s205230 (18 reset windows from exact optimized reset subblocks).
set raw [open cdc_raw.rpt];set rawtext [read $raw];close $raw
set severe [regexp -all -inline -line {^CDC-[0-9]+[ \t]+(?:Critical|Warning)[ \t]+[0-9]+.*$} $rawtext]
if {[llength $severe]!=1 || ![regexp {^CDC-13[ \t]+Critical[ \t]+2[ \t]} [lindex $severe 0]]} {error "CDC differs from reviewed two-path case: $severe"}
set fifos [get_cells -hier -filter {REF_NAME == FIFO36E1}]
if {[llength $fifos]!=2} {error "Expected precisely two VDMA FIFO36E1 primitives"}
foreach dir {MM2S S2MM} edge {rd wr} {
 set prefix "backend/backend_i/dma/U0/GEN_SPRT_FOR_${dir}.${dir}_LINEBUFFER_I"
 set fifo [filter $fifos "NAME =~ $prefix/*"]
 if {[llength $fifo]!=1} {error "FIFO identity $dir"}
 if {[get_property EN_SYN $fifo] ni {0 FALSE false} || [get_property DO_REG $fifo]!=1} {error "Unsupported primitive reset mode"}
 set resets [get_cells -hier -filter "NAME =~ $prefix/*g7ser_birst.rstbt"]
 if {[llength $resets]!=1} {error "Unreviewed reset block"}
 set regname "${resets}/rsync.ric.power_on_${edge}_rst_reg\[0\]"
 set src [get_pins -of_objects [get_cells -hier -filter "NAME == $regname"] -filter {REF_PIN_NAME == C}]
 set dst [get_pins -of_objects $fifo -filter {REF_PIN_NAME == RST}]
 if {[llength $src]!=1 || [llength $dst]!=1} {error "Exact waiver pins not found"}
 if {[string first [get_property NAME $src] $rawtext]<0 || [string first [get_property NAME $dst] $rawtext]<0} {error "Path not present in raw CDC evidence"}
 create_waiver -type CDC -id CDC-13 -from $src -to $dst -user R10_offline_review -description "Exact AXI VDMA 6.3 7-series FIFO36E1 asynchronous RST; EN_SYN=0 DO_REG=1; UG473 internal reset synchronization. R8 reset subblocks passed 18 exact-netlist windows; VDMA config, clocks and reset wrapper unchanged here. Native IP functional recovery and source gating verified. Not a waiver for video data CDC or timing."
}
write_waivers fifo_reset_review.xdc
report_cdc -details -file cdc_reviewed.rpt
report_waivers -file waiver_review.rpt
set f [open cdc_reviewed.rpt];set t [read $f];close $f
if {[regexp -line {^CDC-[0-9]+[ \t]+(Critical|Warning)[ \t]+[1-9]} $t]} {error "Unresolved CDC remains"}
puts "EXACT_TWO_FIFO_RST_PATHS_REVIEWED_NO_GENERAL_CDC_SUPPRESSION"
