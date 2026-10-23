#!/usr/bin/env python3
"""
=============================================================================
File: lob_telemetry_visualizer.py
Description: Real-Time Terminal Visualizer for Nexys A7 FPGA Limit Order Book
             Receives hardware telemetry streamed over USB-UART (/dev/ttyUSB1)
             at 115200 baud and renders an animated BBO order book & spread.
=============================================================================
Usage:
  python3 tools/lob_telemetry_visualizer.py             # Connects to /dev/ttyUSB1
  python3 tools/lob_telemetry_visualizer.py --demo      # Demo / simulation mode
  python3 tools/lob_telemetry_visualizer.py --port /dev/ttyUSB0
=============================================================================
"""

import sys
import os
import time
import re
import argparse
import random

try:
    import serial
    import serial.tools.list_ports
    HAS_SERIAL = True
except ImportError:
    HAS_SERIAL = False

# ANSI Color Codes
RESET   = "\033[0m"
BOLD    = "\033[1m"
DIM     = "\033[2m"
GREEN   = "\033[1;32m"
RED     = "\033[1;31m"
YELLOW  = "\033[1;33m"
CYAN    = "\033[1;36m"
BLUE    = "\033[1;34m"
MAGENTA = "\033[1;35m"
WHITE   = "\033[1;37m"
BG_BLUE = "\033[44m"
CLEAR   = "\033[2J\033[H"

# Regex pattern matching hardware BBO frame: [BBO] B:<hex> | A:<hex>
BBO_PATTERN = re.compile(
    r"\[BBO\]\s+B:([0-9A-Fa-f]+)\s*\|\s*A:([0-9A-Fa-f]+)(?:\s*\|\s*O:([0-9A-Fa-f]+))?"
)
STATUS_PATTERN = re.compile(r"\|\s*V:([01])\s*\|\s*E:([0-9A-Fa-f]{2})")

class LOBVisualizer:
    def __init__(self, port="/dev/ttyUSB1", baud=115200, demo=False, raw=False):
        self.port = port
        self.baud = baud
        self.demo = demo
        self.raw = raw
        
        # Market State
        self.best_bid = 0.0
        self.best_ask = 0.0
        self.prev_bid = 0.0
        self.prev_ask = 0.0
        self.active_orders = 0
        self.book_valid = False
        self.error_code = 0
        self.event_count = 0
        self.quote_changes = 0
        self.start_time = time.time()
        self.last_update_time = None
        self.log_history = []
        self.max_history = 6

    def format_price(self, hex_val):
        """Converts raw integer tick price into dollar format (tick size = $0.0001)."""
        try:
            val = int(hex_val, 16)
            # Default NASDAQ ITCH price unit is 1/10000th of a dollar (4 decimals)
            return val / 10000.0
        except ValueError:
            return 0.0

    def add_log(self, msg):
        timestamp = time.strftime("%H:%M:%S")
        self.log_history.append(f"[{timestamp}] {msg}")
        if len(self.log_history) > self.max_history:
            self.log_history.pop(0)

    def process_line(self, line):
        m = BBO_PATTERN.search(line)
        if m:
            status_match = STATUS_PATTERN.search(line)
            previous_valid = self.book_valid
            if status_match:
                self.book_valid = status_match.group(1) == "1"
                self.error_code = int(status_match.group(2), 16)
            else:
                # Compatibility with the original 31-byte telemetry frame.
                self.book_valid = True
                self.error_code = 0
            if previous_valid and not self.book_valid:
                self.add_log(f"BOOK INVALID: error 0x{self.error_code:02X}; reset and replay required")
            self.prev_bid = self.best_bid
            self.prev_ask = self.best_ask
            self.best_bid = self.format_price(m.group(1))
            self.best_ask = self.format_price(m.group(2))
            if m.group(3):
                self.active_orders = int(m.group(3), 16)
            self.event_count += 1
            self.last_update_time = time.time()
            if self.book_valid and (self.best_bid != self.prev_bid or self.best_ask != self.prev_ask):
                self.quote_changes += 1
                self.add_log(f"BBO CHANGED: BID=${self.best_bid:.4f} | ASK=${self.best_ask:.4f}")
            return True
        elif line.strip():
            self.add_log(f"RAW: {line.strip()}")
            return False

    def render(self):
        elapsed = time.time() - self.start_time
        hz = (self.event_count / elapsed) if elapsed > 0 else 0.0
        spread = (self.best_ask - self.best_bid) if (self.best_ask > 0 and self.best_bid > 0) else 0.0
        spread_ticks = int(round(spread * 10000)) if spread > 0 else 0

        # Trend indicators
        bid_arrow = "▲" if self.best_bid > self.prev_bid else ("▼" if self.best_bid < self.prev_bid else " ")
        ask_arrow = "▲" if self.best_ask > self.prev_ask else ("▼" if self.best_ask < self.prev_ask else " ")

        buf = []
        buf.append(CLEAR)
        buf.append(f"{CYAN}=============================================================================={RESET}")
        buf.append(f"{BOLD}{WHITE}   AMD/Xilinx Artix-7 FPGA Limit Order Book (LOB) Hardware Monitor{RESET}")
        buf.append(f"   Board: {YELLOW}Digilent Nexys A7-100T{RESET} | Telemetry: {GREEN}USB-UART @ {self.baud} Baud{RESET}")
        buf.append(f"{CYAN}=============================================================================={RESET}")

        # Status Line
        status_color = GREEN if (self.demo or (self.last_update_time and time.time() - self.last_update_time < 3.0)) else YELLOW
        mode_str = f"{MAGENTA}[DEMO MODE]{RESET}" if self.demo else f"{GREEN}[LIVE /dev/ttyUSB]{RESET}"
        buf.append(f" Status: {mode_str} | Port: {BOLD}{self.port}{RESET} | Frames: {BOLD}{self.event_count}{RESET} | Quote changes: {BOLD}{self.quote_changes}{RESET} | Rate: {BOLD}{hz:.1f} Hz{RESET}")
        if not self.book_valid and self.event_count:
            buf.append(f" {RED}{BOLD}BOOK INVALID — error 0x{self.error_code:02X}; reset and replay the feed{RESET}")
        buf.append(f"{CYAN}------------------------------------------------------------------------------{RESET}")

        # Order Book Ladder (BBO Display)
        buf.append(f"{BOLD}{WHITE}                           TOP OF BOOK (BBO){RESET}\n")
        
        bid_str = f"${self.best_bid:8.4f}" if self.book_valid and self.best_bid > 0 else "   --.----"
        ask_str = f"${self.best_ask:8.4f}" if self.book_valid and self.best_ask > 0 else "   --.----"
        if not self.book_valid:
            bid_arrow = ask_arrow = " "

        buf.append(f"       {GREEN}{BOLD}┌──────────────────────┐{RESET}          {RED}{BOLD}┌──────────────────────┐{RESET}")
        buf.append(f"       {GREEN}{BOLD}│   BEST BID (BUY)     │{RESET}          {RED}{BOLD}│   BEST ASK (SELL)    │{RESET}")
        buf.append(f"       {GREEN}{BOLD}├──────────────────────┤{RESET}          {RED}{BOLD}├──────────────────────┤{RESET}")
        buf.append(f"       {GREEN}{BOLD}│  {bid_str}  {bid_arrow}     │{RESET}  {YELLOW}◀SPREAD▶{RESET} {RED}{BOLD}│  {ask_str}  {ask_arrow}     │{RESET}")
        buf.append(f"       {GREEN}{BOLD}└──────────────────────┘{RESET}          {RED}{BOLD}└──────────────────────┘{RESET}")

        # Spread Banner
        if not self.book_valid and self.event_count:
            buf.append(f"\n                        {BOLD}Spread: {RED}Unavailable (invalid book){RESET}\n")
        elif self.best_bid > 0 and self.best_ask > 0:
            if spread >= 0:
                spread_str = f"${spread:.4f} ({spread_ticks} ticks)"
                buf.append(f"\n                        {BOLD}Spread: {YELLOW}{spread_str}{RESET}\n")
            else:
                crossed_ticks = abs(int(round(spread * 10000)))
                crossed_str = f"-${abs(spread):.4f} (-{crossed_ticks} ticks) [CROSSED BOOK: BID > ASK]"
                buf.append(f"\n               {BOLD}Spread: {RED}{crossed_str}{RESET}\n")
        elif self.best_bid > 0 or self.best_ask > 0:
            buf.append(f"\n                        {BOLD}Spread: {YELLOW}One-Sided Market{RESET}\n")
        else:
            buf.append(f"\n                        {BOLD}Spread: {DIM}Awaiting Market Data...{RESET}\n")

        buf.append(f"{CYAN}------------------------------------------------------------------------------{RESET}")
        buf.append(f"{BOLD} Live Telemetry Activity Log:{RESET}")
        if not self.log_history:
            buf.append(f"   {DIM}Listening for serial frames from FPGA USB-UART (Micro-USB J6 / {self.port})...{RESET}")
        else:
            for item in self.log_history:
                buf.append(f"   {DIM}{item}{RESET}")
        
        buf.append(f"{CYAN}=============================================================================={RESET}")
        buf.append(f" {DIM}Press Ctrl+C to exit.{RESET}")

        sys.stdout.write("\n".join(buf) + "\n")
        sys.stdout.flush()

    def run_demo(self):
        """Simulates incoming FPGA telemetry frames for demonstration and testing."""
        print("[*] Starting LOB Visualizer in DEMO mode...")
        time.sleep(1)
        sim_bid = 905000  # $90.5000
        sim_ask = 910000  # $91.0000
        
        try:
            while True:
                # Random walk order book movement
                delta = random.choice([-200, -100, 0, 100, 200])
                sim_bid = max(890000, sim_bid + delta)
                sim_ask = max(sim_bid + 100, sim_ask + random.choice([-100, 0, 100]))
                
                # Format exactly as hardware uart_telemetry.v emits:
                # [BBO] B:<8 hex digits> | A:<8 hex digits>\r\n
                raw_frame = f"[BBO] B:{sim_bid:08X} | A:{sim_ask:08X}\r\n"
                self.process_line(raw_frame)
                self.render()
                time.sleep(random.uniform(0.3, 0.8))
        except KeyboardInterrupt:
            print("\n[*] Demo stopped.")

    def run_serial(self):
        if not HAS_SERIAL:
            print(f"{RED}[ERROR] pyserial is not installed.{RESET}")
            print("Please run: uv pip install pyserial")
            sys.exit(1)

        print(f"[*] Opening serial monitor on {self.port} @ {self.baud} baud...")
        try:
            ser = serial.Serial(self.port, self.baud, timeout=0.2)
        except Exception as e:
            print(f"{RED}[ERROR] Could not open {self.port}: {e}{RESET}")
            ports = [p.device for p in serial.tools.list_ports.comports()]
            if ports:
                print(f"[*] Available serial ports detected: {ports}")
            print(f"[*] Tip: You can test the display immediately with: python3 tools/lob_telemetry_visualizer.py --demo")
            sys.exit(1)

        print(f"[*] Connected to {self.port}! Listening for FPGA telemetry...")
        self.render()
        
        try:
            while True:
                line = ser.readline()
                if line:
                    try:
                        text = line.decode('utf-8', errors='replace').strip()
                        if text:
                            try:
                                with open('/tmp/vis_frames.log', 'a') as f:
                                    f.write(f"{text}\n")
                            except Exception:
                                pass
                            self.process_line(text)
                            self.render()
                    except Exception:
                        pass
                else:
                    if self.last_update_time and time.time() - self.last_update_time > 1.0:
                        self.render()
                time.sleep(0.01)
        except KeyboardInterrupt:
            print("\n[*] Exiting LOB Visualizer.")
            ser.close()

def main():
    parser = argparse.ArgumentParser(description="Nexys A7 FPGA Limit Order Book Terminal Visualizer")
    parser.add_argument("--port", default="/dev/ttyUSB1", help="Serial port (default: /dev/ttyUSB1)")
    parser.add_argument("--baud", type=int, default=115200, help="Baud rate (default: 115200)")
    parser.add_argument("--demo", action="store_true", help="Run in self-contained demo/simulation mode")
    parser.add_argument("--test", action="store_true", help="Run 3 iterations of demo and exit (for unit testing)")
    args = parser.parse_args()

    vis = LOBVisualizer(port=args.port, baud=args.baud, demo=args.demo or args.test)
    
    if args.test:
        for i in range(3):
            vis.process_line(f"[BBO] B:{900000 + i*100:08X} | A:{905000 + i*100:08X}\r\n")
            vis.render()
            time.sleep(0.05)
        print("\n[PASS] Visualizer render test passed!")
        sys.exit(0)
    elif args.demo:
        vis.run_demo()
    else:
        vis.run_serial()

if __name__ == "__main__":
    main()
