"""Figure 2 - LOB system architecture (target design, v6 candidate sizes).
Sources: architecture context (sec. 3, 4, 8), earlier phase-one draft in Git history,
docs/mmio.md. Only rv32m_unit / CPU / bus / IMEM / DMEM exist in RTL today."""
from dg import Fig, NAVY

f = Fig(1700, 1170)
f.title("Figure 2 - RV32IM + pure-hardware Limit Order Book: system architecture",
        "Nexys A7-100T (XC7A100T)  |  RMII Ethernet -> MoldUDP64 / ITCH 5.0 -> hardware LOB  |  "
        "3 clock domains  |  sizes are v6 candidates, not synthesis results")

# =============== clk_eth domain ===============
f.region(40, 86, 1620, 184, "clk_eth  50 MHz  -  RMII receive, parse, canonical events")
Y, H = 125, 90
f.box(60, Y, 140, H, ["LAN8720A", "CRS_DV, RXD[1:0]", "REF_CLK 50 MHz"], kind="plain", title="PHY (external)", size=9)
f.box(230, Y, 170, H, ["2b -> byte, SFD strip", "FCS CRC32 check", "runt / overrun drop"], kind="new", title="RMII RX + MAC", size=9)
f.box(430, Y, 150, H, ["2 banks, ownership", "no overwrite while", "parser owns bank"], kind="new", title="Packet RAM", size=9)
f.box(610, Y, 150, H, ["EtherType, IPv4 hdr", "length, no fragments", "UDP length / port"], kind="new", title="IPv4 + UDP", size=9)
f.box(790, Y, 150, H, ["session, seq[63:0]", "message count", "gap / dup / stale"], kind="new", title="MoldUDP64", size=9)
f.box(970, Y, 150, H, ["A F E C X D U", "length per type", "unsupported -> flag"], kind="new", title="ITCH 5.0 parser", size=9)
f.box(1160, Y, 210, H, ["opcode[2:0], side", "order_id[63:0]", "price_idx[14:0], shares[27:0]"], kind="new", title="Canonical event gen", size=9)
for a, b in ((200, 230), (400, 430), (580, 610), (760, 790), (940, 970), (1120, 1160)):
    f.arrow([(a, 170), (b, 170)])
f.text(60, 238, "rx byte[7:0], valid, last -> frame_ok, len -> ip payload -> mold msgs -> itch msg -> event[127:0]", 9, fill="#333")
f.text(60, 252, "error counters: bad FCS, malformed, unsupported, dropped, seq gap, buffer overflow", 9, fill="#333")
f.arrow([(1370, 170), (1540, 170), (1540, 236)], label="event[127:0], valid / ready", lp=(1455, 163), lsize=9)
f.box(1440, 236, 200, 64, ["512 x 128b, gray pointers", "wr 50 MHz | rd 100 MHz"], kind="new", title="Async event FIFO", size=9)

# =============== clk_core domain ===============
f.region(40, 270, 1620, 740, "clk_core  100 MHz  -  CPU, system bus, LOB, recovery")
f.box(60, 310, 200, 76, ["RV32IM, 3-stage", "IF+ID | EX | MEM+WB"], title="CPU core (Fig. 1)", size=9)
f.box(300, 310, 330, 76, ["100 MHz in (E3) -> MMCM", "clk_core 100 | clk_eth 50 | phy_ref 50 @ 45 deg | clk_vga 25.175",
                          "async assert, sync release reset per domain"], kind="new", title="Clock + reset", size=9)
f.box(60, 412, 1120, 26, ["system bus:  req_valid, req_write, req_addr[31:0], req_wdata[31:0], req_wstrb[3:0]   |   "
                          "rsp_valid, rsp_rdata[31:0], rsp_error"], size=9, align="left")
f.arrow([(160, 386), (160, 412)], both=True)
SY = 470
for x, w, t, ln, k in ((60, 130, "IMEM", ["0x0000_0000", "16 KB BRAM"], "old"),
                       (210, 130, "DMEM", ["0x2000_0000", "16 KB BRAM"], "old"),
                       (360, 200, "LOB MMIO", ["0x4000_0000 (proposed)", "ctrl, BBO, counters"], "new"),
                       (620, 250, "Net stats", ["0x5000_0000 (proposed)", "pkt / err / gap counters"], "new"),
                       (900, 150, "default error", ["unmapped address", "-> rsp_error"], "old")):
    f.box(x, SY, w, 50, ln, kind=k, title=t, size=9)
    f.arrow([(x + w / 2, 438), (x + w / 2, SY)], both=True)
f.arrow([(850, 215), (850, SY)], dashed=True, label="error / seq counters, CDC 50->100", lp=(858, 330), anchor="start", lsize=9)

f.box(1250, 360, 190, 100, ["gap / error -> BOOK_VALID = 0", "GLIMPSE load, seq reconcile", "replay, then BOOK_VALID = 1"],
      kind="new", title="Recovery controller", size=9)
f.arrow([(1180, 425), (1250, 425)], both=True)
f.arrow([(1300, 360), (1300, 215)], dashed=True, label="replay / inject", lp=(1308, 300), anchor="start", lsize=9)


# ---------------- LOB core ----------------
f.region(60, 552, 1380, 430, "Hardware LOB core  (correctness-first sequencer, one RAM op in flight)", color=NAVY)
MY = 590
f.box(80, MY, 230, 100, ["2048 sets x 4 way", "CRC32-C(order_id)[10:0]", "order_id -> slot[11:0]"], kind="new", title="Order-ID hash", size=9)
f.box(330, MY, 140, 100, ["16-entry assoc", "overflow ways", "full -> fail-stop"], kind="new", title="Stash", size=9)
f.box(490, MY, 170, 100, ["4096 x 12b", "init, pop, push", "underflow check"], kind="new", title="Free list", size=9)
f.box(680, MY, 230, 100, ["4096 x ~114b", "id, side, price, shares", "valid bit"], kind="new", title="Order slot RAM", size=9)
f.box(930, MY, 240, 100, ["64K x 32b, addr={side,price}", "qty += / -=", "under / overflow check"], kind="new", title="Price-level RAM", size=9)
f.box(1200, MY, 220, 100, ["Add Exec Cancel Delete", "Replace: Del+Add, fail->invalid", "commit point, ack, fail"], kind="new", title="Op sequencer", size=9)
f.raw('<line x1="195" y1="722" x2="1310" y2="722" stroke="#1a1a1a" stroke-width="1.6"/>')
for cx in (195, 400, 575, 795, 1050, 1310):
    f.arrow([(cx, 690), (cx, 722)], both=True)
f.text(200, 738, "sequencer address / data / strobe to each RAM (scheduled, no shared-port conflicts)", 9, halo=True)

f.box(80, 770, 820, 96, ["Add: pop free -> hash insert -> slot write -> price += -> occupancy set",
                         "Execute / Cancel: hash lookup -> slot read -> price -= -> slot update; occupancy clear at 0",
                         "Delete: lookup -> price -= -> slot free, hash remove, free push",
                         "Side and price always come from the stored slot, never from E / C / X fields"],
      kind="plain", title="Operation schedules (to be proven per RAM latency)", size=9, align="left")
f.box(80, 880, 820, 84, ["quantity under/overflow, duplicate or missing order ID, stash full,",
                         "FIFO overflow, malformed message  ->  error counter + BOOK_VALID = 0",
                         "assertions on the 10 LOB invariants, reference-model compare in sim"],
      kind="plain", title="Invariants and fail-stop", size=9, align="left")

f.box(930, 770, 240, 96, ["L0: 32b reg", "L1: 32 x 32b LUTRAM", "L2: 1K x 32b BRAM / side"], kind="new", title="Occupancy hierarchy", size=9)
f.arrow([(1050, 690), (1050, 770)], both=True, label="set / clear", lp=(1056, 745), anchor="start", lsize=9)
f.box(1200, 770, 220, 96, ["best bid = highest set", "best ask = lowest set", "price, qty, empty flag"], kind="new", title="BBO search", size=9)
f.arrow([(1170, 818), (1200, 818)])
f.box(1200, 884, 220, 80, ["req / ack, coherent copy", "bid, ask, qty, BOOK_VALID"], kind="new", title="BBO snapshot regs", size=9)
f.arrow([(1310, 866), (1310, 884)])

# FIFO read side into sequencer, MMIO / recovery links
f.arrow([(1540, 300), (1540, 640), (1420, 640)], label="event[127:0] (clk_core)", lp=(1548, 480), anchor="start", lsize=9)
f.arrow([(460, 520), (460, 533)], both=True)
f.raw('<circle cx="460" cy="541" r="8" fill="white" stroke="#1a1a1a"/>')
f.text(460, 544.5, "A", 9, True, "middle")
f.text(476, 545, "A = BBO snapshot req/ack, BOOK_VALID, LOB counters, init / clear", 9)
f.raw('<circle cx="1180" cy="924" r="8" fill="white" stroke="#1a1a1a"/>')
f.text(1180, 927.5, "A", 9, True, "middle")
f.arrow([(1188, 924), (1200, 924)], both=True)
f.arrow([(1345, 460), (1345, 590)], dashed=True, label="inject / valid", lp=(1352, 520), anchor="start", lsize=9)

# =============== VGA domain ===============
f.region(40, 1022, 1100, 128, "clk_vga  25.175 MHz  -  640 x 480 @ 60 Hz")
f.box(60, 1050, 220, 80, ["BBO, depth, status", "from snapshot (no LOB port)"], kind="new", title="Book view reader", size=9)
f.box(310, 1050, 220, 80, ["write: core side", "read: pixel side (mapping TBD)"], kind="new", title="Framebuffer RAM", size=9)
f.box(560, 1050, 200, 80, ["H/V counters", "text + bars", "1 read per pixel"], kind="new", title="VGA renderer", size=9)
f.box(790, 1050, 330, 80, ["vga_hs, vga_vs", "vga_r[3:0], vga_g[3:0], vga_b[3:0]"], kind="plain", title="Nexys A7 VGA DAC (resistor ladder)", size=9)
for a, b in ((280, 310), (530, 560), (760, 790)):
    f.arrow([(a, 1090), (b, 1090)])
f.arrow([(1310, 964), (1310, 1004), (270, 1004), (270, 1050)], dashed=True,
        label="snapshot handshake, CDC 100 -> 25.175", lp=(740, 998), lsize=9)

# =============== legend ===============
f.box(1180, 1022, 480, 128, [], kind="plain", shadow=0)
f.text(1192, 1042, "Legend", 11, True)
f.box(1192, 1054, 30, 16, kind="old", shadow=3)
f.text(1232, 1067, "in RTL today (CPU, bus, IMEM, DMEM)", 10)
f.box(1192, 1080, 30, 16, kind="new", shadow=3)
f.text(1232, 1093, "to be built (not yet in rtl/)", 10)
f.text(1192, 1118, "dashed arrow = status / control or CDC path; solid = data path", 10)
f.text(1192, 1136, "Sizes are v6 candidates; BRAM mapping not yet synthesized", 10)

open("fig2_lob.svg", "w").write(f.svg())
print("ok")
