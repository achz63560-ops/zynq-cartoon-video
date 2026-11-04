set xsa [file normalize [lindex $argv 0]]
set out [file normalize [lindex $argv 1]]
puts [help {hsi generate_app}]
set h [hsi::open_hw_design $xsa]
hsi::generate_app -hw $h -os standalone -proc ps7_cortexa9_0 -app zynq_fsbl -compile -dir $out
puts "HSI_FSBL_OFFLINE_PASS"
hsi::close_hw_design $h
exit
