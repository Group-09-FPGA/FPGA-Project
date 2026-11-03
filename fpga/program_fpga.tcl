# =============================================================================
# File: program_fpga.tcl
# Description: Programs the Digilent Nexys A7-100T (xc7a100t_0) with top_system.bit
# =============================================================================

if {$argc > 0} {
    set BIT_FILE [file normalize [lindex $argv 0]]
} else {
    set BIT_FILE [file normalize [file join [file dirname [info script]] "../build/keyboard_vga_720p/top_system.bit"]]
}

if {![file exists $BIT_FILE]} {
    puts "ERROR: Bitstream not found at $BIT_FILE"
    exit 1
}

puts "Connecting to hardware target and programming FPGA..."
puts "Bitstream: $BIT_FILE"

open_hw_manager
connect_hw_server -allow_non_jtag

set targets [get_hw_targets]
puts "Available Hardware Targets: $targets"

if {[llength $targets] == 0} {
    puts "ERROR: No hardware targets detected! Ensure Nexys A7 is powered on and connected via USB."
    exit 1
}

open_hw_target [lindex $targets 0]
set devices [get_hw_devices]
puts "Available Hardware Devices: $devices"

set dev [lindex [get_hw_devices xc7a100t*] 0]
if {$dev == ""} {
    set dev [lindex [get_hw_devices] 0]
}

puts "Targeting Device: $dev"
current_hw_device $dev
refresh_hw_device -update_hw_probes false $dev

set_property PROGRAM.FILE $BIT_FILE $dev
program_hw_devices $dev
refresh_hw_device $dev

puts "=========================================================="
puts "SUCCESS: FPGA successfully programmed with top_system.bit!"
puts "=========================================================="
close_hw_target
close_hw_manager
