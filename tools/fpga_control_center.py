#!/usr/bin/env python3
"""
=============================================================================
File: fpga_control_center.py
Description: Interactive CLI Control Center for Nexys A7 FPGA LOB System
             - Dynamic USB-UART Serial Port & Network Interface Detection
             - FPGA Bitstream Programming via Vivado Hardware Manager
             - Telemetry Terminal Visualizer Launcher (Ptyxis window/tab or in-place)
             - Ethernet MoldUDP64 / ITCH 5.0 Market Feed Packet Generator
             - 1-Click End-to-End Automated Hardware Demonstration Pipeline
=============================================================================
"""

import sys
import os
import subprocess
import time
import json
import shutil
import glob
from pathlib import Path

# ANSI Colors
RESET   = "\033[0m"
BOLD    = "\033[1m"
DIM     = "\033[2m"
RED     = "\033[1;31m"
GREEN   = "\033[1;32m"
YELLOW  = "\033[1;33m"
BLUE    = "\033[1;34m"
MAGENTA = "\033[1;35m"
CYAN    = "\033[1;36m"
WHITE   = "\033[1;37m"
BG_BLUE = "\033[44;1;37m"

REPO_ROOT = Path(__file__).resolve().parent.parent
TOOLS_DIR = REPO_ROOT / "tools"
VIVADO_SCRIPTS_DIR = REPO_ROOT / "vivado" / "scripts"

try:
    import serial.tools.list_ports
    HAS_SERIAL = True
except ImportError:
    HAS_SERIAL = False


def print_banner():
    banner = f"""
{CYAN}{BOLD}╔════════════════════════════════════════════════════════════════════════════════╗
║                {WHITE}FPGA LIMIT ORDER BOOK (LOB) CONTROL CENTER{CYAN}                      ║
║           {DIM}Hardware Target: Digilent Nexys A7-100T (XC7A100T-1CSG324C){CYAN}           ║
╚════════════════════════════════════════════════════════════════════════════════╝{RESET}
"""
    print(banner)


def get_serial_ports():
    """Returns detected serial ports categorized into USB/ACM and legacy ports."""
    ports = []
    if HAS_SERIAL:
        for p in serial.tools.list_ports.comports():
            dev = p.device
            desc = p.description or ""
            hwid = p.hwid or ""
            is_usb = any(x in dev for x in ["ttyUSB", "ttyACM"]) or "USB" in hwid or "FTDI" in desc or "Digilent" in desc
            ports.append({
                "device": dev,
                "desc": desc,
                "hwid": hwid,
                "is_usb": is_usb
            })
    else:
        # Fallback via /dev scan
        for dev in sorted(glob.glob("/dev/ttyUSB*") + glob.glob("/dev/ttyACM*")):
            ports.append({
                "device": dev,
                "desc": "USB Serial Device",
                "hwid": "",
                "is_usb": True
            })

    # Sort USB first, then device name
    ports.sort(key=lambda x: (not x["is_usb"], x["device"]))
    return ports


def get_network_interfaces():
    """Returns active network interfaces with IPv4 addresses and broadcast targets."""
    ifaces = []
    try:
        out = subprocess.check_output(["ip", "-j", "addr"], stderr=subprocess.DEVNULL).decode()
        data = json.loads(out)
        for item in data:
            ifname = item.get("ifname", "")
            state = item.get("operstate", "UNKNOWN")
            ipv4_list = []
            bcast_list = []
            for a in item.get("addr_info", []):
                if a.get("family") == "inet":
                    local = a.get("local")
                    if local:
                        ipv4_list.append(local)
                    bcast = a.get("broadcast")
                    if bcast:
                        bcast_list.append(bcast)
            ifaces.append({
                "name": ifname,
                "state": state,
                "ips": ipv4_list,
                "broadcasts": bcast_list,
                "is_active": state.upper() == "UP" and bool(ipv4_list)
            })
    except Exception:
        pass

    # Sort active interfaces first
    ifaces.sort(key=lambda x: (not x["is_active"], x["name"]))
    return ifaces


def get_bitstream_files():
    """Scans repository and parent hardware directory for bitstream files."""
    candidates = []
    # Primary build location
    default_bit = REPO_ROOT / "build_system" / "top_system.bit"
    if default_bit.exists():
        candidates.append(default_bit)

    # Search in repo
    for p in REPO_ROOT.glob("**/*.bit"):
        if p not in candidates and ".Xil" not in p.parts:
            candidates.append(p)

    # Search in parent hardware directory
    hw_parent = REPO_ROOT.parent
    if hw_parent.exists():
        for p in hw_parent.glob("**/*.bit"):
            if p not in candidates and ".Xil" not in p.parts and "fpga-lob" not in p.parts:
                candidates.append(p)

    return candidates


def print_system_status():
    """Prints current hardware detection summary."""
    usb_ports = [p for p in get_serial_ports() if p["is_usb"]]
    ifaces = [i for i in get_network_interfaces() if i["is_active"]]
    bits = get_bitstream_files()
    vivado_path = shutil.which("vivado") or os.path.expanduser("~/.local/bin/vivado")
    has_vivado = os.path.exists(vivado_path)

    print(f"{BOLD}[System Status & Detected Hardware]{RESET}")

    # Vivado Toolchain
    if has_vivado:
        print(f"  {GREEN}✔ Vivado EDA:{RESET}       {vivado_path}")
    else:
        print(f"  {YELLOW}⚠ Vivado EDA:{RESET}       Not found in PATH or ~/.local/bin/vivado")

    # Bitstream Status
    if bits:
        print(f"  {GREEN}✔ FPGA Bitstream:{RESET}   {bits[0].name} ({bits[0]})")
    else:
        print(f"  {YELLOW}⚠ FPGA Bitstream:{RESET}   No .bit files found in build_system/ (will prompt)")

    # Serial Ports
    if usb_ports:
        port_names = ", ".join([f"{p['device']} ({p['desc']})" for p in usb_ports])
        print(f"  {GREEN}✔ USB Serial Ports:{RESET} {port_names}")
    else:
        print(f"  {YELLOW}⚠ USB Serial Ports:{RESET} No /dev/ttyUSB* detected (Plug Nexys A7 USB cable & power ON)")

    # Network
    if ifaces:
        if_desc = ", ".join([f"{i['name']} [{i['ips'][0]}]" for i in ifaces])
        print(f"  {GREEN}✔ Active Network:{RESET}   {if_desc}")
    else:
        print(f"  {YELLOW}⚠ Active Network:{RESET}   No active IPv4 interfaces found")

    print("-" * 80)


def choose_serial_port():
    """Interactive prompt to select or enter a serial port."""
    ports = get_serial_ports()
    usb_ports = [p for p in ports if p["is_usb"]]

    print(f"\n{BOLD}Select Serial UART Port for Telemetry:{RESET}")
    options = []

    if usb_ports:
        print(f"  {CYAN}Detected USB Serial Devices:{RESET}")
        for idx, p in enumerate(usb_ports):
            desc = p['desc'] if p['desc'] else p['hwid']
            is_def = " (Recommended for Nexys A7 UART)" if "USB1" in p['device'] else ""
            print(f"    [{idx + 1}] {GREEN}{p['device']}{RESET} - {desc}{YELLOW}{is_def}{RESET}")
            options.append(p['device'])
    else:
        print(f"  {YELLOW}No active USB serial ports detected (/dev/ttyUSB*, /dev/ttyACM*).{RESET}")
        print(f"  {DIM}(If Nexys A7 is plugged in, UART is typically /dev/ttyUSB1){RESET}")

    custom_idx = len(options) + 1
    print(f"    [{custom_idx}] Enter custom port path manually (e.g. /dev/ttyUSB1)")
    sim_idx = len(options) + 2
    print(f"    [{sim_idx}] Run in Simulated Demo Mode (--demo)")

    while True:
        try:
            choice = input(f"\n{BOLD}Enter choice [1-{sim_idx}]: {RESET}").strip()
            if not choice:
                if usb_ports:
                    pref = next((p['device'] for p in usb_ports if "USB1" in p['device']), usb_ports[0]['device'])
                    return pref, False
                else:
                    return "/dev/ttyUSB1", False

            ch = int(choice)
            if 1 <= ch <= len(options):
                return options[ch - 1], False
            elif ch == custom_idx:
                manual = input(f"Enter custom serial device path [/dev/ttyUSB1]: ").strip()
                return manual if manual else "/dev/ttyUSB1", False
            elif ch == sim_idx:
                return "/dev/ttyUSB1", True
            else:
                print(f"{RED}Invalid option, try again.{RESET}")
        except ValueError:
            print(f"{RED}Please enter a number.{RESET}")


def choose_network_target():
    """Interactive prompt to select network interface or broadcast IP."""
    ifaces = get_network_interfaces()
    active_ifaces = [i for i in ifaces if i["is_active"]]

    print(f"\n{BOLD}Select Network Interface / Target IP for Market Feed (MoldUDP64):{RESET}")
    options = []

    # Common FPGA subnet broadcast defaults
    presets = [
        {"desc": "Standard FPGA Subnet Broadcast (Default Nexys IP 192.168.1.10)", "ip": "192.168.1.255"},
        {"desc": "Local Loopback (127.0.0.1 - for local testbench & simulation)", "ip": "127.0.0.1"}
    ]

    opt_idx = 1
    print(f"  {CYAN}Detected Active Interfaces:{RESET}")
    for i in active_ifaces:
        bcast = i["broadcasts"][0] if i["broadcasts"] else i["ips"][0]
        print(f"    [{opt_idx}] Interface {GREEN}{i['name']}{RESET} -> Broadcast: {YELLOW}{bcast}{RESET} (Local IP: {i['ips'][0]})")
        options.append(bcast)
        opt_idx += 1

    print(f"  {CYAN}Standard Presets:{RESET}")
    for p in presets:
        is_rec = " (Recommended for Direct Ethernet Cable)" if "192.168.1" in p['ip'] else ""
        print(f"    [{opt_idx}] {p['desc']} -> {YELLOW}{p['ip']}{RESET}{GREEN}{is_rec}{RESET}")
        options.append(p['ip'])
        opt_idx += 1

    custom_idx = opt_idx
    print(f"    [{custom_idx}] Enter custom IP address manually")

    while True:
        try:
            choice = input(f"\n{BOLD}Enter choice [1-{custom_idx}] (default 192.168.1.255): {RESET}").strip()
            if not choice:
                return "192.168.1.255"
            ch = int(choice)
            if 1 <= ch <= len(options):
                return options[ch - 1]
            elif ch == custom_idx:
                manual = input("Enter target IP address: ").strip()
                return manual if manual else "192.168.1.255"
            else:
                print(f"{RED}Invalid option, try again.{RESET}")
        except ValueError:
            print(f"{RED}Please enter a number.{RESET}")


def choose_bitstream():
    """Interactive prompt to select or enter a bitstream path."""
    bits = get_bitstream_files()
    print(f"\n{BOLD}Select FPGA Bitstream (.bit file):{RESET}")
    options = []

    if bits:
        for idx, b in enumerate(bits):
            is_rec = " (Project Main Bitstream)" if "top_system.bit" in b.name else ""
            print(f"    [{idx + 1}] {GREEN}{b.name}{RESET} - {b}{YELLOW}{is_rec}{RESET}")
            options.append(str(b))

    custom_idx = len(options) + 1
    print(f"    [{custom_idx}] Enter custom .bit file path manually")

    while True:
        try:
            choice = input(f"\n{BOLD}Enter choice [1-{custom_idx}]: {RESET}").strip()
            if not choice:
                if options:
                    return options[0]
                return str(REPO_ROOT / "build_system" / "top_system.bit")
            ch = int(choice)
            if 1 <= ch <= len(options):
                return options[ch - 1]
            elif ch == custom_idx:
                manual = input("Enter custom .bit file path: ").strip()
                return manual
            else:
                print(f"{RED}Invalid option, try again.{RESET}")
        except ValueError:
            print(f"{RED}Please enter a number.{RESET}")


def launch_in_terminal(cmd_list, title="Terminal", mode="window"):
    """
    Spawns command in Ptyxis terminal or falls back to in-process execution.
    mode: 'window' | 'tab' | 'inplace'
    """
    has_ptyxis = shutil.which("ptyxis") is not None
    cmd_str = " ".join(cmd_list)

    if mode == "window" and has_ptyxis and "DISPLAY" in os.environ:
        ptyxis_cmd = ["ptyxis", "--new-window", "-T", title, "--"] + cmd_list
        try:
            proc = subprocess.Popen(ptyxis_cmd, cwd=str(REPO_ROOT))
            print(f"{GREEN}[✔] Launched in new Ptyxis window (PID: {proc.pid}){RESET}")
            return proc
        except Exception as e:
            print(f"{YELLOW}[⚠] Failed to launch window via Ptyxis ({e}), falling back to in-place...{RESET}")

    elif mode == "tab" and has_ptyxis and "DISPLAY" in os.environ:
        ptyxis_cmd = ["ptyxis", "--tab", "-T", title, "--"] + cmd_list
        try:
            proc = subprocess.Popen(ptyxis_cmd, cwd=str(REPO_ROOT))
            print(f"{GREEN}[✔] Launched in new Ptyxis tab (PID: {proc.pid}){RESET}")
            return proc
        except Exception as e:
            print(f"{YELLOW}[⚠] Failed to launch tab via Ptyxis ({e}), falling back to in-place...{RESET}")

    # Fallback / In-place execution
    print(f"{CYAN}[*] Running in-place: {cmd_str}{RESET}\n")
    try:
        subprocess.run(cmd_list, cwd=str(REPO_ROOT))
    except KeyboardInterrupt:
        print(f"\n{YELLOW}[*] Process terminated by user.{RESET}")
    return None


def action_program_fpga():
    """Programs the FPGA using Vivado hardware manager."""
    print(f"\n{BOLD}{CYAN}=== Action: Program Nexys A7 FPGA ==={RESET}")
    bit_file = choose_bitstream()

    if not os.path.exists(bit_file):
        print(f"{RED}[ERROR] Bitstream file does not exist: {bit_file}{RESET}")
        return

    vivado_bin = shutil.which("vivado") or os.path.expanduser("~/.local/bin/vivado")
    if not os.path.exists(vivado_bin):
        print(f"{RED}[ERROR] Vivado launcher not found! Expected at {vivado_bin}{RESET}")
        return

    tcl_script = VIVADO_SCRIPTS_DIR / "program_fpga.tcl"
    print(f"\n{CYAN}[*] Launching Vivado Hardware Manager in batch mode...{RESET}")
    print(f"    Bitstream:  {bit_file}")
    print(f"    TCL Script: {tcl_script}")

    cmd = [vivado_bin, "-mode", "batch", "-source", str(tcl_script), "-tclargs", str(bit_file)]
    try:
        subprocess.run(cmd, cwd=str(REPO_ROOT), check=True)
        print(f"\n{GREEN}{BOLD}[✔] FPGA Successfully Programmed!{RESET}")
    except subprocess.CalledProcessError as e:
        print(f"\n{RED}[ERROR] Vivado programming failed (exit code {e.returncode}).{RESET}")
        print(f"{YELLOW}Check that:{RESET}")
        print("  1. The Nexys A7 board is connected via USB and powered ON.")
        print("  2. Vivado hardware server / cable drivers have permission (sudo / udev rules).")
    except KeyboardInterrupt:
        print(f"\n{YELLOW}[*] Programming cancelled by user.{RESET}")


def action_launch_telemetry():
    """Configures and launches the LOB telemetry terminal visualizer."""
    print(f"\n{BOLD}{CYAN}=== Action: Launch Telemetry Terminal Visualizer ==={RESET}")
    port, is_demo = choose_serial_port()

    baud = "115200"
    if not is_demo:
        baud_choice = input(f"Enter UART Baud Rate [115200]: ").strip()
        if baud_choice:
            baud = baud_choice

    print(f"\n{BOLD}Choose Terminal Window Mode:{RESET}")
    print(f"  [1] Open in New Window ({GREEN}Recommended - Ptyxis standalone window{RESET})")
    print(f"  [2] Open in New Tab (Ptyxis tab)")
    print(f"  [3] Run in Current Terminal (In-place)")

    mode_map = {"1": "window", "2": "tab", "3": "inplace"}
    choice = input("Enter choice [1-3] (default 1): ").strip()
    mode = mode_map.get(choice, "window")

    script_path = TOOLS_DIR / "lob_telemetry_visualizer.py"
    cmd = [sys.executable, str(script_path)]
    if is_demo:
        cmd.append("--demo")
        title = "LOB Telemetry [SIMULATION DEMO]"
    else:
        cmd.extend(["--port", port, "--baud", baud])
        title = f"Nexys A7 Telemetry [{port}]"

    launch_in_terminal(cmd, title=title, mode=mode)


def action_send_packets():
    """Run the narrated, UART-confirmed one-order-at-a-time journey."""
    print(f"\n{BOLD}{CYAN}=== Action: Single-Order FPGA Journey ==={RESET}")
    target_ip = choose_network_target()
    uart_port, is_demo = choose_serial_port()
    interval = input("Seconds between orders [10; use 1 for faster demo]: ").strip() or "10"
    count = input("Number of orders [10; 0 for continuous]: ").strip() or "10"
    cmd = [sys.executable, str(TOOLS_DIR / "order_journey.py"),
           "--target-ip", target_ip, "--uart-port", uart_port,
           "--interval", interval, "--count", count]
    if is_demo:
        cmd.append("--demo")
    launch_in_terminal(cmd, mode="inplace")


def action_full_pipeline():
    """1-Click end-to-end hardware demonstration pipeline."""
    print(f"\n{BOLD}{CYAN}=== 🚀 One-Click Automated FPGA Demonstration Pipeline ==={RESET}")
    print("This pipeline will:")
    print("  1. Program the Nexys A7 FPGA with the synthesized LOB bitstream")
    print("  2. Open UART telemetry in this terminal")
    print("  3. Send one ITCH order at a time with board-verified stage counters")
    print("-" * 80)

    # 1. Hardware port selection
    port, is_demo = choose_serial_port()
    target_ip = choose_network_target()
    bit_file = choose_bitstream()

    proceed = input(f"\n{BOLD}Ready to launch full pipeline? [Y/n]: {RESET}").strip().lower()
    if proceed and proceed != 'y':
        print(f"{YELLOW}[*] Pipeline aborted.{RESET}")
        return

    # Step 1: Program FPGA
    print(f"\n{BOLD}[Step 1/3] Programming FPGA...{RESET}")
    if not is_demo:
        vivado_bin = shutil.which("vivado") or os.path.expanduser("~/.local/bin/vivado")
        tcl_script = VIVADO_SCRIPTS_DIR / "program_fpga.tcl"
        if os.path.exists(vivado_bin) and os.path.exists(bit_file):
            try:
                cmd = [vivado_bin, "-mode", "batch", "-source", str(tcl_script), "-tclargs", str(bit_file)]
                subprocess.run(cmd, cwd=str(REPO_ROOT), check=True)
                print(f"{GREEN}[✔] FPGA successfully programmed!{RESET}")
            except Exception as e:
                print(f"{RED}[⚠] FPGA programming had an error: {e}{RESET}")
                cont = input("Continue launching telemetry and packets anyway? [Y/n]: ").strip().lower()
                if cont and cont != 'y':
                    return
        else:
            print(f"{YELLOW}[⚠] Vivado or bitstream not found, skipping programming step.{RESET}")
    else:
        print(f"{CYAN}[*] Demo mode: Skipping physical FPGA programming.{RESET}")

    time.sleep(1)

    print(f"\n{BOLD}[Step 2/3] Opening UART telemetry in this terminal...{RESET}")
    print(f"\n{BOLD}[Step 3/3] Starting narrated single-order feed...{RESET}")
    interval = input("Seconds between orders [10]: ").strip() or "10"
    journey_cmd = [sys.executable, str(TOOLS_DIR / "order_journey.py"),
                   "--target-ip", target_ip, "--uart-port", port,
                   "--interval", interval]
    if is_demo:
        journey_cmd.append("--demo")
    launch_in_terminal(journey_cmd, mode="inplace")


def action_demo_simulation():
    """Runs telemetry and packet feed simultaneously in software demo mode."""
    print(f"\n{BOLD}{CYAN}=== Action: Software Simulation / Demo Mode ==={RESET}")
    print("Launching animated telemetry visualizer in demonstration mode...")
    telem_script = TOOLS_DIR / "lob_telemetry_visualizer.py"
    cmd = [sys.executable, str(telem_script), "--demo"]
    launch_in_terminal(cmd, title="LOB Telemetry Visualizer [DEMO MODE]", mode="window")


def main_menu():
    """Main interactive menu loop."""
    while True:
        os.system("clear" if os.name == "posix" else "cls")
        print_banner()
        print_system_status()

        print(f"{BOLD}Select an action to perform:{RESET}")
        print(f"  [{GREEN}1{RESET}] 🔌 {BOLD}Program FPGA{RESET}                (Connect JTAG & download top_system.bit)")
        print(f"  [{GREEN}2{RESET}] 📊 {BOLD}Launch Telemetry Terminal{RESET}   (Real-time USB-UART BBO order book monitor)")
        print(f"  [{GREEN}3{RESET}] 🌐 {BOLD}Single-Order FPGA Journey{RESET} (Narrated pipeline + board UART proof)")
        print(f"  [{CYAN}4{RESET}] 🚀 {BOLD}{CYAN}1-Click Complete Pipeline{RESET}   (Program FPGA + Open Telemetry + Stream Feed)")
        print(f"  [{MAGENTA}5{RESET}] 🧪 {BOLD}Demo / Simulation Mode{RESET}      (Run visualizer in standalone demo mode)")
        print(f"  [{YELLOW}6{RESET}] 🔄 {BOLD}Rescan Hardware Devices{RESET}     (Re-scan USB ports, Ethernet, & bitstreams)")
        print(f"  [{RED}0{RESET}] 🚪 {BOLD}Exit{RESET}")
        print("-" * 80)

        choice = input(f"{BOLD}Enter choice [0-6]: {RESET}").strip()

        if choice == "1":
            action_program_fpga()
            input(f"\n{DIM}Press Enter to return to main menu...{RESET}")
        elif choice == "2":
            action_launch_telemetry()
            input(f"\n{DIM}Press Enter to return to main menu...{RESET}")
        elif choice == "3":
            action_send_packets()
            input(f"\n{DIM}Press Enter to return to main menu...{RESET}")
        elif choice == "4":
            action_full_pipeline()
            input(f"\n{DIM}Press Enter to return to main menu...{RESET}")
        elif choice == "5":
            action_demo_simulation()
            input(f"\n{DIM}Press Enter to return to main menu...{RESET}")
        elif choice == "6":
            print(f"\n{CYAN}[*] Rescanning hardware ports and devices...{RESET}")
            time.sleep(0.5)
        elif choice in ["0", "q", "exit"]:
            print(f"\n{CYAN}Goodbye!{RESET}")
            sys.exit(0)
        else:
            print(f"{RED}Invalid option '{choice}', please choose [0-6].{RESET}")
            time.sleep(1)


if __name__ == "__main__":
    try:
        main_menu()
    except KeyboardInterrupt:
        print(f"\n\n{CYAN}Exited Control Center.{RESET}")
        sys.exit(0)
