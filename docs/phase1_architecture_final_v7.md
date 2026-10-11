# Phase 1 Architecture Specification v7 (independent audit of v5; supersedes the unverified v6 draft)

**Status:** NOT READY for full LOB RTL implementation (see §27).
**Date:** 2026-10-10. **Scope:** architecture only; no RTL, testbench, XDC or firmware was modified.
**Why v7:** `docs/phase1_architecture_final_v6.md` already existed in the working tree (untracked, 72 KB, not committed). It was not overwritten. v7 re-derives every claim independently.

Evidence tags: [RV] repository-verified, [PS] protocol-supported, [DS] datasheet-supported, [CALC] calculated, [DD] design decision, [UNV] unverified, [BLK] blocker.

## 1. Executive summary and readiness verdict

**Verdict: NOT READY.** The LOB core itself (data structures, schedules, BBO, memory budget) is now specified to implementable precision, but P0-G (recovery) and the board/clock/timing evidence cannot be closed from the available evidence:

| # | Blocker | Why open |
|---|---|---|
| B1 | GLIMPSE closing-sequence semantics | GLIMPSE spec PDF could not be retrieved (server returned HTML). Next-vs-last sequence is [UNV]. |
| B2 | No snapshot transport | The FPGA has no TCP/SoupBinTCP stack and no TX path. Snapshot must come via CPU/host injection; unimplemented and unspecified upstream. |
| B3 | Recovery buffer horizon | A finite buffer only covers about 1-4 ms of wire-rate traffic (§19). Recovery is conditional on snapshot-load time. |
| B4 | Nexys A7 ETH_REFCLK direction | Digilent reference manual returned HTTP 403. The XDC lists `ETH_REFCLK` pin D5 as a port [RV-external], and the LAN8720A supports both clock modes [DS]. Board wiring is not primary-source confirmed. |
| B5 | CPU clock | `top_fpga.v` divides the CPU clock to 1 Hz (`CLK_DIV_COUNT=49_999_999`). 100 MHz operation is not hardware-verified [RV: `docs/rv32m_final_audit.md`]. |
| B6 | Hash capacity | Guarantee is probabilistic (workload assumption) plus fail-stop, not mathematical (§12). |
| B7 | No synthesis/P&R evidence | No LOB RTL exists; every primitive count below is analytical. |

Main v5 corrections: price indexing, 2-beat replace, hash (2048x4 -> 1024x8, 2048 orders), hierarchical occupancy, per-op cycle schedules, bounded recovery contract, legal VGA mapping, analytical BRAM inventory (111 RAMB18 = ~56 of 135 RAMB36-equivalent, not 132; synthesis-unconfirmed).

## 2. Scope, requirements, assumptions, exclusions

- [DD] One instrument per run (single stock locate, MMIO-configured). Multi-instrument is excluded.
- [DD] 2,048 resting orders maximum; 8,192 price levels per side (16,384 total).
- [DD] RX only. No Ethernet TX, ARP, IGMP or MoldUDP64 re-request transmission. Multicast/unicast filtering is by configured destination MAC/IP/port.
- [DD] The feed is a recorded or replayed ITCH 5.0 stream over MoldUDP64 sent from a PC at <= 100 Mbps, not the live 10G NASDAQ feed. (NASDAQ requires 10/40 Gb connectivity for the live FPGA feed [PS: NQTVITCHspecification.pdf p.~6].)
- [DD] Supported book messages: A, F, E, C, X, D, U. All other types advance the sequence and produce no event.
- Exclusions: matching engine, order-type semantics beyond displayed shares, trade-break handling, crossed-book resolution, multi-symbol.

## 3. Repository baseline and evidence classification

| Item | Value | Tag |
|---|---|---|
| Path | `/home/ronit/acad/current/hardware/fpga-lob` is a symlink to `/home/ronit/acad/sem-3/hardware/fpga-lob` | [RV] |
| Branch / HEAD | `main`, `7c2134f84706c82ec88efd0a24b01552755fb966`, tracking `origin/main` | [RV] |
| Working tree | Dirty: many modified/deleted `sim/unit/**` Vivado artifacts, untracked `docs/phase1_architecture_final_v4/v5/v6.md`, `docs/write_v4.py`, `docs/write_v5.py`, `generate_phase1.py`, `phase1_architecture_final_v3.md`, `docs/diagrams/`, `docs/block_diagram.html`. Preserved untouched. | [RV] |
| Tools | Vivado/xvlog at `/tools/Xilinx/2026.1/Vivado/bin`; `pdftotext`, `python3` available | [RV] |
| Primary sources read | NASDAQ ITCH 5.0 PDF, MoldUDP64 V1.00 PDF, LAN8720A datasheet DS00002165C, UG473 v1.11, Digilent master XDC | [PS]/[DS] |
| Not retrievable | Digilent Nexys A7 reference manual (403), GLIMPSE spec, UG473 current rev, Nexys schematic | [UNV] |

## 4. Existing implementation inventory

- [RV] Implemented: `rtl/cpu/core/` (`cpu_core`, `decoder`, `alu`, `rv32m_unit`, `hazard_unit`, `forwarding_unit`, `sys_bus_interconnect`, `imem_slave`, `dmem_slave`, `memory`, `seven_seg_driver`, `top_fpga`), `rtl/cpu/lab5_baseline`.
- [RV] Empty directories (no RTL): `rtl/{bus,clocking,common,display,ethernet,itch,lob,matching,network,telemetry,top}`. Empty docs: `ethernet.md itch.md lob.md vga.md clocking.md resource-budget.md verification.md requirements.md matching.md`.
- [RV] `constraints/nexys_a7.xdc` has no ETH or VGA pins constrained (grep returned nothing).
- [RV] `sys_bus_interconnect.v` decodes only `addr[31:28]==0` (IMEM), `==2 or F` (DMEM). Anything else gets a 1-cycle `rsp_error`. No accelerator slave port exists.
- [RV] `build/post_route_timing.rpt`: all constraints met with the CPU on the 1 Hz generated `slow_clk`; the 100 MHz net `clk` only clocks the divider and 47 endpoints. This is not evidence of 100 MHz CPU closure.
- [RV] Existing synthesis (core only): 1 RAMB36 (IMEM), 4 DSP48E1; DMEM is LUTRAM.
- Verified testing: simulation artifacts for `cpu_core` exist (`sim/unit/core/*.log`); no LOB/Ethernet/ITCH test exists.

## 5. System architecture and module interfaces

Pipeline: `RMII PHY -> eth_rmii_rx -> eth_mac_rx(FCS) -> pkt_buf[2 banks] -> pkt_parser (IPv4/UDP/Mold/ITCH, 2-pass) -> evt_fifo (async) -> lob_seq -> {hash, slot, free_stack, price_ram, occ} -> bbo regs -> mmio_lob -> sys_bus_interconnect -> cpu_core`.

| Module | Clock | Key interface (all synchronous to its clock) |
|---|---|---|
| `eth_rmii_rx` | clk_eth | in `crs_dv, rxd[1:0], rxerr`; out `byte_valid, byte_data[7:0], frame_start, frame_end, rx_err` |
| `eth_mac_rx` | clk_eth | in byte stream; out `wr_en, wr_addr[10:0], wr_data[7:0], bank_sel, frame_done, frame_len[10:0], fcs_ok` |
| `pkt_buf` | clk_eth | 2 x 2K x 9 (RAMB18); ownership `own[1:0]` (0=RX,1=PARSER,2=FREE) |
| `pkt_parser` | clk_eth | out `evt_valid, evt_ready, evt_data[255:0]` (valid/ready, transfer on both high) |
| `evt_fifo` | wr clk_eth / rd clk_core | FIFO36E1 x4, 512 x 288 (256 used), FWFT, `full` back-pressures parser |
| `lob_seq` | clk_core | `evt_rd_en, evt_q[255:0], evt_empty`; memories as §12-14; out `bbo_*`, `book_valid`, `fail_code[7:0]` |
| `mmio_lob` | clk_core | CPU bus signals exactly as `sys_bus_interconnect`: `req_valid, req_write, req_addr[31:0], req_wdata[31:0], req_wstrb[3:0] -> rsp_valid, rsp_rdata[31:0]` |
| `vga_ctrl` | clk_vga | `hsync, vsync, rgb`, reads framebuffer port B |

Ownership rule: every memory has exactly one writer FSM (single-owner); the only multi-writer structure is the TDP commit described in §16.

## 6. Clock domains, reset, CDC, timing constraints

| Domain | Freq | Source | Tag |
|---|---|---|---|
| clk_core | 100 MHz | `CLK100MHZ` pin E3 (Digilent XDC) -> MMCM/BUFG | [DS] pin; [DD] |
| clk_eth | 50 MHz | MMCM output -> BUFG for fabric, and ODDR -> `ETH_REFCLK` (pin D5) | [DD]; B4 |
| clk_vga | ~25.175 MHz | MMCM (Clocking Wizard, <=0.5% error acceptable) | [DD] |

**PHY clock direction (B4).** LAN8720A has two modes selected by the nINTSEL strap: `nINTSEL=0` PHY sources REF_CLK on nINT/REFCLKO; `nINTSEL=1` (default pull-up) REF_CLK must be driven externally on XTAL1/CLKIN [DS: LAN8720A DS00002165C §3.7.4, Table 3-6]. The Digilent XDC exposes `ETH_REFCLK` (D5) and `ETH_INTN` (B8) as FPGA pins [RV-external: Digilent master XDC], which is consistent with REF_CLK In mode (FPGA drives 50 MHz, nINT is a separate interrupt). The Nexys A7 manual/schematic could not be fetched (HTTP 403), so the strap value is **[UNV]**. Gate: read schematic before RTL. Fallback: if the PHY is in REF_CLK Out mode, `ETH_REFCLK` must be an input clocked via a BUFG, not an output.

**PHY timing [DS].** In REF_CLK In mode RXD/CRS_DV/RXER output valid <= 14.0 ns after the rising CLKIN edge; TXD/TXEN setup 4.0 ns [DS §5 timing, notes 5-25]. With a 20 ns period the RX input window is 6 ns minus FPGA-internal skew; this must be closed with `set_input_delay` relative to the generated clock at the ODDR output and checked in Vivado (P&R item, not proven here).

**Reset.** Each domain has an async-assert, sync-deassert synchronizer (2 FF, `ASYNC_REG`) released only after the MMCM `LOCKED` and the external button are stable. Release order: clk_eth and clk_vga domains first, clk_core last; `lob_init` starts only when both remote domains report `reset_done` (single-bit 2FF levels).

**CDC inventory (the only crossings).**

| # | Crossing | Mechanism |
|---|---|---|
| 1 | events eth->core (256 b) | FIFO36E1 async FIFO (built-in gray pointers) |
| 2 | config core->eth (stock locate, MAC/IP/port, session) | toggle req/ack 4-phase handshake; data bus held stable until ack; writes allowed only while `ENABLE=0` |
| 3 | eth counters -> core | eth domain latches counters on toggle request; core reads after toggle ack |
| 4 | single-bit flags (reset_done, link) | 2FF synchronizer |
| 5 | framebuffer core->vga | true dual-port BRAM with independent clocks; `frame_start` pulse via 2FF-level toggle |
No multi-bit bus passes through independent 2FF synchronizers.

**Constraints to validate in Vivado (not claimed met):** `create_clock` on E3 (10 ns); MMCM auto-generated clocks; `create_generated_clock` for ETH_REFCLK ODDR; `set_clock_groups -asynchronous` between the three domains, with `set_max_delay -datapath_only` on the handshake data buses; XDC for ETH/VGA pins (currently absent, [RV]).

**CPU clock [BLK B5].** `top_fpga.v` currently runs the CPU from a 1 Hz divided `slow_clk` [RV]. MMIO assumes the CPU shares clk_core. Requirement: replace the divided clock with a clock-enable (or run at clk_core). 100 MHz CPU timing (WNS +0.420 ns exploratory, [RV: rv32m_final_audit.md]) is not hardware-verified.

## 7. Ethernet/RMII receive architecture

- RMII RX is 2 bits per 50 MHz clock; one byte per 4 clocks (80 ns/byte) [CALC: 100 Mbps / 8 = 12.5 MB/s].
- Frame start: CRS_DV=1 and preamble `01` dibits until SFD (`01 01 ... 11`, bytes 0x55.. then 0xD5, LSB-first dibits). RXER=1 anywhere in the frame marks `rx_err`.
- Frame end: CRS_DV low. RMII allows CRS_DV to toggle at 25 MHz on loss of carrier while the PHY FIFO drains; frame end is declared when CRS_DV is low for 2 consecutive clocks, and the final partial byte (non-multiple of 4 dibits) discards the frame [UNV: exact RMII behavior is from the RMII spec, not read]. Counter `RX_ERR_FRAMES`.
- Accepted length (dst MAC through FCS): 64..1518 bytes. Runt (<64) and giant (>1518, no VLAN support) dropped. Stored frame bytes: <= 1514 (FCS not stored).
- FCS: CRC-32 (poly 0x04C11DB7, reflected, init 0xFFFFFFFF) over dst..FCS; pass iff residue = 0xC704DD7B [standard Ethernet; Protocol-supported by IEEE 802.3, not retrieved here]. Frames failing FCS are dropped before parser ownership.
- Dst MAC: configured unicast, or IPv4 multicast `01:00:5E:xx:xx:xx` when `CFG_MCAST_EN`; else drop (`MAC_FILTER_DROPS`).

## 8. Packet buffering and ownership

- Two banks, each 2048 x 9 as one RAMB18 (SDP-style: port A write by MAC, port B read by parser, both clk_eth). 1514 B < 2048, so one frame fits per bank. 9th bit unused (reserved 0).
- Ownership FSM per bank: `FREE -> RX_FILL -> (fcs_ok ? PARSE : FREE) -> FREE`. The MAC selects the next FREE bank on `frame_start`; if none is FREE the frame is dropped (`PKT_DROP_NOBUF`). A bank is released only by the parser at `pkt_done`.
- Buffer-full behavior: parser holds its bank while `evt_ready=0`; the MAC keeps filling the other bank; a third frame arriving while both are held is dropped, which later appears as a Mold sequence gap. No payload is overwritten in place (a bank is never written while owned by the parser).
- Parser read: 1 byte/clk@50 MHz (>=400 Mbit/s equivalent vs 100 Mbit/s wire), so a frame is parsed in far less than the frame time (§20).

## 9. IPv4/UDP/MoldUDP64/ITCH parser (two-pass)

Pass 1 (validate, no events) then pass 2 (emit). Pass 1 prevents emitting events from a packet that is later found malformed.

| Layer | Check | Failure action |
|---|---|---|
| Ethernet | ethertype 0x0800 | drop, `NON_IPV4` |
| IPv4 | version=4, IHL=5, proto=17, MF=0 and fragment offset=0, header checksum ones-complement = 0xFFFF, `total_len` in [20+8+20, frame_len-14] (pad bytes ignored), dst IP matches config | drop, `IP_BAD` / `FRAG_DROP` |
| UDP | dst port = config; `udp_len == total_len-20`; **checksum not verified** (policy [DD]: FCS covers link integrity; assumption: single-hop LAN, risk accepted) | drop, `UDP_BAD` |
| Mold | payload >= 20 B; session == latched/configured session; message blocks `sum(2+len_i) == udp_payload-20` | drop, `MOLD_BAD` |
| ITCH | per type exact length [PS: ITCH 5.0 offsets, verified from the PDF]: A=36, F=40, E=31, C=36, X=23, D=19, U=35 | wrong length for a supported type -> `ITCH_BAD`, packet dropped, **book invalidated** (stream untrusted) |

Mold header [PS: MoldUDP64 V1.00 PDF]: session 10 B @0, sequence number 8 B @10 (first message in packet), message count 2 B @18; count 0 = heartbeat, 0xFFFF = end of session; heartbeats and EOS packets carry the *next expected* sequence number; message block = 2-byte length (excludes itself) + data; all big-endian.

Unsupported type (e.g. S, R, H, P, Q, ...) with any length: skipped, counted `ITCH_UNSUPPORTED`, sequence still consumed. Messages whose Stock Locate (offset 1, 2 B [PS]) differs from `CFG_LOCATE`: skipped (`ITCH_FILTERED`). Only after pass 1 passes does pass 2 emit events; `NEXT_SEQ` advances to `S+C` at the end of pass 2.
Parser throughput: pass 2 reads the length (2 B) and message bytes serially at 1 B/clk: 19 B D -> ~21 clk = 420 ns @50 MHz per message, one event per message, two events never from one message (Replace is a single compound event, §10).

## 10. Canonical event schema and validation (P0-B)

[DD] Event = **256 bits**, version 1. Replace is ONE compound event (a 128-bit event cannot carry two 64-bit IDs; ITCH `U` carries no side, so splitting into Delete+Add at the parser is impossible: the side lives only in the book [PS: ITCH 5.0 §1.4.5]).

| Bits | Field | Meaning |
|---|---|---|
| [255:252] | `ver` | 4'h1. Any other value -> `FAIL_EVT_FORMAT` |
| [251:248] | `op` | 1 ADD, 2 EXEC, 3 CANCEL, 4 DELETE, 5 REPLACE; 0, 6-15 illegal |
| [247] | `side` | 0 bid, 1 ask. ADD only |
| [246:240] | rsvd | must be 0 |
| [239:176] | `oid` | ITCH order reference (ADD: new order; EXEC/CANCEL/DELETE: target; REPLACE: original) |
| [175:112] | `noid` | REPLACE new reference; else 0 |
| [111:80] | `shares` | ADD/EXEC/CANCEL/REPLACE shares (>=1); DELETE: 0 |
| [79:67] | `pidx` | 13-bit price index (ADD, REPLACE); else 0; 0 when `oow`=1 |
| [66] | `oow` | price unsupported (ADD, REPLACE) |
| [65:64] | rsvd | must be 0 |
| [63:32] | `seq` | low 32 bits of the Mold message sequence (debug/trace only) |
| [31:0] | rsvd | must be 0 |

Validity per op (all unlisted fields must be 0; lob_seq checks in C1, violation = `FAIL_EVT_FORMAT`, fail-stop): ADD {side,oid,shares>=1,pidx|oow}; EXEC {oid,shares>=1}; CANCEL {oid,shares>=1}; DELETE {oid}; REPLACE {oid,noid,shares>=1,pidx|oow}. Compatibility: `ver` is bumped on any layout change; lob_seq rejects unknown versions.

**Wire -> event map [PS: ITCH 5.0 PDF, offsets verified].**

| Wire | Len | Used fields (offset) | Event |
|---|---|---|---|
| A | 36 | locate 1, oid 11, B/S 19, shares 20, price 32 | ADD |
| F | 40 | same as A (MPID @36 ignored) | ADD |
| E | 31 | oid 11, shares 19 (match 23 ignored) | EXEC |
| C | 36 | oid 11, shares 19; printable 31 and exec price 32 ignored: execution does not change the resting display price; the level is the order's stored level | EXEC |
| X | 23 | oid 11, cancelled shares 19 | CANCEL |
| D | 19 | oid 11 | DELETE |
| U | 35 | orig oid 11, new oid 19, shares 27, price 31 | REPLACE |

Shares semantics [PS]: E/C/X shares are *deductions* from remaining displayed shares, cumulative; the order dies at 0. B/S byte other than `B`/`S` in A/F -> `ITCH_BAD`, packet dropped, book invalidated. Zero shares in A/F/E/C/X/U -> `ITCH_BAD`.

## 11. LOB data model and order lifecycle (P0-C overview)

Order states: FREE slot (on stack) -> LIVE (hash entry + slot + level qty + occupancy) -> FREE.
**Invariants (checked by the reference model and SVA):**
I1 every LIVE slot has exactly one hash/stash entry (key=oid, slot=index) and every valid entry points to a LIVE slot;
I2 free-stack contents plus LIVE slots partition 0..2047 exactly;
I3 `level_qty[side][idx] == sum(shares of LIVE slots with that side/idx)`;
I4 occupancy bit set <=> `level_qty != 0`; L1 bit <=> leaf word != 0; L0 bit <=> L1 group != 0;
I5 best registers equal the extremum of occupancy whenever `op_busy=0`.

Failure policy (every row is fail-stop: `book_valid<=0`, `fail_code` latched, event intake halted, FIFO drained/ignored, until CPU `CLEAR`):

| Condition | Detected | State mutated? |
|---|---|---|
| Duplicate oid on ADD / REPLACE new id | C4 (ADD) / pre-phase (U) | No |
| Missing oid on EXEC/CANCEL/DELETE/REPLACE and `BOOK_EXACT=1` | after hash lookup | No |
| Missing oid and `BOOK_EXACT=0` | same | No; ignored, counter `MISS_ID_IGN` |
| Slot stack empty | C4 | No |
| Hash set + stash full | C4 | No |
| Level qty overflow (32-bit carry) | C5 | No |
| Underflow: EXEC/CANCEL shares > remaining | after slot read | No |
| Event format | C1 | No |
Because every check precedes the commit edge (§16), **no failure leaves a partial mutation**. The only way to get a partial state is reset/SEU mid-commit, handled by clearing the book (§22). `BOOK_EXACT`: cleared when an out-of-window price is rejected (§13), set by `CLEAR`.

## 12. Slot table, hash table, stash, free list (P0-C)

**Slot table**: 2048 x 47 b (padded to 54 b, 3 x RAMB18 in 2Kx18, SDP, clk_core). Word: `[46] valid, [45] side, [44:32] pidx, [31:0] shares`. Address = slot[10:0]. Read latency 1 (no output reg).
**Hash table**: 1024 sets x 8 ways, entry 76 b = `{valid, slot[10:0], key[63:0]}`. Each way is a separate memory (5 x RAMB18 in 1Kx18, SDP; 90 b used 76), so one set read returns all 8 ways in one cycle (latency 1) and a write updates one way (per-way write enable). Set index `h = oid[9:0] ^ oid[19:10] ^ oid[29:20] ^ oid[39:30] ^ oid[49:40] ^ oid[59:50] ^ {6'b0,oid[63:60]}` (10 bits).
**Stash**: 8 entries x 77 b in FFs/LUTs, fully parallel compare; searched in the same cycle as the hash compare. Entries never migrate; freed on delete.
**Free list**: LIFO stack, 2048 x 11 b (2 x RAMB18 2Kx9), `sp[11:0]` register. Pop: read `stack[sp-1]` (latency 1), commit decrements `sp`; push: write `stack[sp]=slot`, `sp+1`. A LIFO has no head/tail pointer race, and push/pop never occur in the same op (Replace reuses the slot).

**Capacity analysis [CALC].** Model: keys uniform, set occupancy ~ Poisson(N/1024) independent; overflow = sum max(0,K-8). Script `/tmp/v7calc/hash3.py`, run in this audit.

| Organisation / live orders N | E[stash use] | P(stash>0) | P(stash>8) |
|---|---|---|---|
| v5: 2048x4, N=2048 | 8.91 | 0.999 | 0.515 (P>16 = 2.4e-2) |
| v5: 2048x4, N=4096 | 153.9 | 1.0 | 1.0 |
| **v7: 1024x8, N=2048** | 0.301 | 0.216 | **2.9e-6** (P>16 = 9.4e-12) |

With an 8-entry stash the failure probability at a *full* 2048-order book is ~2.9e-6 per full-book state under the uniform-hash assumption. **Established:** the v5 organisation provably cannot hold 4096 orders (expected overflow 153.9 > 16). **Workload assumption:** uniform spreading of `oid`s (real ITCH references are mostly increasing counters, favourable to the XOR fold, but UNV). **Not guaranteed:** an adversarial set of 17 IDs to one set always overflows (8 ways + 8 stash + 1). Therefore hash/stash exhaustion is fail-stop, not recoverable. [BLK B6 remains, accepted risk R2]

## 13. Price-level memory and price normalization (P0-A)

[PS] Price(4): 4-byte unsigned integer with 4 implied decimals; maximum in TotalView-ITCH 200,000.0000 = 2,000,000,000 = 0x77359400 [ITCH 5.0 Data Types]. A 15-bit truncation covers only $3.2767: rejected.

MMIO config (write only while `ENABLE=0`): `PRICE_BASE` (raw units of $0.0001), `TICK` (raw units, >=1). Parser (clk_eth): `d = price - BASE`; unsupported (`oow=1`, `pidx=0`) if `price < BASE`, `d % TICK != 0`, or `d / TICK >= 8192`; else `pidx = d / TICK`. Division is a 13-iteration shift-subtract (the range pre-check `d < 8192*TICK` bounds the quotient to 13 bits), run during message reception, adding no per-message latency. Example: tick $0.01 -> `TICK=100`; window = 8192 ticks = $81.92. Single instrument: messages with `locate != CFG_LOCATE` are filtered.

**Price-level RAM**: 16384 x 32 b, address `{side, pidx[12:0]}` (14 b; `side=0` bid). Entry = remaining displayed shares at the level (aggregate). Mapping: 16 x RAMB36 at 1Kx36 (32 b used), SDP, clk_core, `DOB_REG=1`, a registered 16:1 output mux -> **read latency 3 cycles** (addr in cycle t, data valid t+3). Overflow: 32-bit carry-out -> `FAIL_QTY_OVF`. Underflow cannot occur on a consistent book (I3); a decrement larger than the level -> `FAIL_QTY_UF`. Bid and ask are separated by the address MSB. Crossed book is not resolved (both sides tracked independently).

## 14. Occupancy hierarchy and BBO (P0-D)

Per side, 8192 price indices, 3 levels:

| Level | Size | Storage | Address |
|---|---|---|---|
| Leaf | 256 words x 32 b | 1 x RAMB18 (512x36 SDP, latency 1) per side | word = `pidx[12:5]`, bit = `pidx[4:0]` |
| L1 | 256 bits | FFs: bit w = (leaf[w] != 0) | group `g=pidx[12:10]`, word `j=pidx[9:5]`: L1 bit = `{g,j}` |
| L0 | 8 bits | FFs: bit g = (L1[g*32+:32] != 0) | `g` |

Cost: 2 RAMB18, 528 FFs, ~two 32-bit priority encoders + one 8-bit per side (~150 LUT; [UNV] estimate).

**Update (only when a level qty crosses 0):** 1 leaf read (prefetched, latency 1) + 1 leaf write in the commit cycle; L1/L0 FF bits update in the same edge from the new word (`word_new==0` clears L1 bit; group==0 clears L0 bit).

**Search (best bid = highest index, best ask = lowest index):** S0: `g=enc(L0)` (reg); S1: `j=enc(L1[g])` (reg); S2: leaf RD addr `{g,j}`; S3: data valid, `m=enc(word)`; S4: `pidx={g,j,m}` (reg); S5: price RD; S8: qty valid; S9: BBO regs written. **Worst-case search = 10 cycles (S0..S9).** Empty book: `L0==0` -> `best_valid=0` after S0.
Fast path (no search): ADD/REPLACE at a better index than best, or onto a side with `best_valid=0`: `best<=pidx`, qty from the commit data; qty change at the best index: qty from commit data. Search is required only when the best level's qty becomes 0.

**Coherence.** Live BBO regs (`bid_valid,bid_pidx,bid_qty,ask_*`, `bbo_gen`) change only in the cycle after commit (or at S9), together, while `op_busy=1`. CPU reads use snapshot regs (§18): `SNAP_REQ` copies live->snapshot when `op_busy=0` in a single cycle. Never claim next-cycle BBO: BBO is visible at ack (add: C7; removal: C11; with search up to +10).

## 15. Complete RAMB18/RAMB36 inventory (P0-E)

Analytical only; **nothing here is synthesis-confirmed [UNV]**. XC7A100T has 135 RAMB36E1 = 270 RAMB18E1 [DS: Artix-7 family]. Legal modes per UG473 v1.11: RAMB36 SDP up to 512x72, 1Kx36, 2Kx18, 4Kx9, 8Kx4, 16Kx2, 32Kx1; RAMB18 SDP 512x36, 1Kx18, 2Kx9, 4Kx4, 8Kx2, 16Kx1; asymmetric read/write widths are allowed [UG473 Summary]; 64Kx1 needs cascade (not used).

| Memory | Logical W x D | Bits | Ports / clock | Latency | Primitive mapping | RAMB18 | Padding |
|---|---|---|---|---|---|---|---|
| Hash ways (8 ways x 1024 sets) | 76 x 1024 per way | 622,592 | SDP: A=write, B=read, clk_core | 1 (no DOB_REG) | per way 5 x RAMB18 (1Kx18) = 90 b | 40 | 14 b/way/set |
| Hash stash | 8 x 77 | 616 | FFs, not BRAM | 0 | registers | 0 | n/a |
| Slot table | 47 x 2048 | 96,256 | SDP, clk_core | 1 | 3 x RAMB18 (2Kx18) = 54 b | 3 | 7 b |
| Free stack | 11 x 2048 | 22,528 | SDP, clk_core | 1 | 2 x RAMB18 (2Kx9) = 18 b | 2 | 7 b |
| Price-level RAM | 32 x 16384 | 524,288 | SDP, clk_core | 3 (BRAM + DOB_REG + mux reg) | 16 x RAMB36 (1Kx36) = 32 RAMB18 | 32 | 4 b/word |
| Occupancy leaf (bid,ask) | 32 x 256 each | 16,384 | SDP, clk_core | 1 | 1 x RAMB18 (512x36) per side | 2 | 4 b + half depth |
| Occupancy L1/L0 | 264 b per side | 528 | FFs | 0 | registers | 0 | n/a |
| Event async FIFO | 256 x 512 (288 wide) | 131,072 | FIFO36E1 wr clk_eth / rd clk_core | FWFT | 4 x FIFO36E1 (512x72) | 8 | 32 b |
| Packet buffers (2 banks) | 8 x 2048 | 32,768 | SDP, clk_eth | 1 | 2 x RAMB18 (2Kx9) | 2 | 1 b |
| VGA framebuffer 320x240x1 | 1 x 76,800 | 76,800 | TDP: A=write clk_core, B=read clk_vga | 1 + 1 mux reg | 3 x RAMB36 (32Kx1, same width on both ports) | 6 | 33,792 b (30.6%) |
| CPU IMEM 16 KB (target) | 32 x 4096 | 131,072 | clk_core | per `imem_slave` | 4 x RAMB36 (1Kx36) | 8 | 0 |
| CPU DMEM 16 KB (target) | 32 x 4096, byte WE | 131,072 | clk_core | per `dmem_slave` | 4 x RAMB36 (1Kx36, 4 byte-WE) | 8 | 0 |
| MMIO / counters / init FSM | - | - | FFs | - | registers | 0 | - |
| **Total** | | | | | | **111 RAMB18 = 55.5 RAMB36-eq** | |

Total ~56 / 135 tiles (41%) [CALC: 111/270]. Contrast: v5 claim 132/135 [UNV, shown unsupported]. Logical-bit division is not used as evidence; the number is the sum of legal mappings. Repository today: 1 RAMB36 used (IMEM 4 KB; DMEM is LUTRAM) [RV], so +7.5 tiles for 16 KB CPU memories is a design decision, not existing.

Checks: (1) hash read and write of the same address in the same cycle never happens (ops serialized, §16), so collision/mode behaviour is don't-care; SDP forces write-first -> NO_CHANGE mapping [UG473 line 295]. (2) Price RAM 16-way depth decomposition is sixteen 1K-deep blocks; the 16:1 read mux is registered (this is the 3-cycle latency, and the routing risk v5 had is bounded to a 16:1 mux). (3) FIFO36E1 at 512x72 is the widest legal FIFO; 256 b needs 4 blocks [UG473; UNV for FIFO36E1 exact modes]. (4) Framebuffer: one 1-bit port write at 100 MHz by the CPU/LOB path; 640x480 at 1 bpp (307,200 b = 10 tiles) is feasible but out of the memory critical path, so the default is 320x240 pixel-doubled to 640x480 timing (read address = {y[8:1], x[9:1]}).
**Initialization:** BRAM contents come from the bitstream INIT (zero) only after configuration; they are NOT re-zeroed by reset. A runtime CLEAR therefore uses an init FSM (§22).

## 16. Cycle schedules (P0-F)

Rules: one event in flight; ports are single-use per cycle by construction. "RD@t" = address presented in cycle t; data is usable in cycle t+L (L: hash 1, slot 1, stack 1, leaf 1, price 3). No read targets an address written in the same cycle or the next cycle (RAW hazard impossible since the commit is the last memory action of an operation and the next operation's first read is >=2 cycles later); if the leaf/level addressed by two reads of the SAME op are equal, the second uses the forwarded value (Replace only).

### 16.1 ADD

| Cyc | Action |
|---|---|
| C0 | `evt_empty=0`: latch event, `evt_rd_en` pulse; `op_busy<=1` |
| C1 | check ver/op/reserved/shares>=1; if `oow` -> `FAIL_PRICE` policy below. Issue RD: hash set h, stack top (`sp-1`), price `{side,pidx}`, leaf word. Stash compare armed |
| C2 | hash data valid: compare 8 ways + stash vs oid -> `hit` (reg); free way/stash slot found; stack data valid |
| C3 | `hit` -> FAIL_DUP. `sp==0` -> FAIL_NOSLOT. no free way and stash full -> FAIL_HASH |
| C4 | price data (L=3) and leaf data valid. `q' = q + shares`, carry -> FAIL_QTY_OVF. new leaf word, `best` decision |
| C5 | **COMMIT** (single cycle, all different memories): hash way write (or stash), slot write `{1,side,pidx,shares}` at slot=`stack_top`, price write, leaf write if q was 0, L1/L0 update, `sp<=sp-1`, `best` fast path update |
| C6 | `done` pulse, counters `EVT_ADD++`, `op_busy<=0` |

Latency 7 cycles (70 ns). Success point: end of C5. Failure paths exit at C3/C4 with zero writes.
Out-of-window price (`oow=1`): action `OOW_POLICY` (MMIO): 0 = fail-stop (default), 1 = drop silently, **set `BOOK_EXACT=0`** (book is now approximate; subsequent missing IDs are tolerated per §11 and a later E/X/D/U of the dropped order is counted `MISS_ID_IGN`).

### 16.2 EXECUTE / CANCEL / DELETE (same datapath; DELETE uses `n=remaining`)

| Cyc | Action |
|---|---|
| C0-C1 | as ADD; RD hash set h |
| C2 | hash data valid; compare -> `hit`, `way`, `slot` (regs) |
| C3 | miss -> FAIL_MISSING (or ignore if `BOOK_EXACT=0`, ack at C4, no write). Hit: RD slot[slot] |
| C4 | slot data valid: `rem`, `side`, `pidx`; `n>rem` -> FAIL_UF. `rem'=rem-n` (DELETE: n=rem) |
| C5 | RD price `{side,pidx}`, RD leaf word (addresses registered in C4) |
| C6 | leaf data valid |
| C7 | (idle: waiting for price latency 3) |
| C8 | price data valid: `q>=n` else FAIL_QTY_UF; `q'=q-n`; `kill=(rem'==0)`; `lvl_zero=(q'==0)`; new leaf word |
| C9 | **COMMIT**: slot write (`rem'`, or valid=0 if kill), price write; if lvl_zero leaf write + L1/L0 update; if kill: hash way invalidate (way/set from C2) + stack write `stack[sp]=slot`, `sp<=sp+1` |
| C10 | `done`; if `lvl_zero` and the level was `best` -> BBO search (§14) else BBO qty fast path |

Latency 11 cycles (110 ns); with best-level removal +10 = 21 cycles (210 ns). Success point: end of C9.

### 16.3 REPLACE (compound; side and slot preserved)

| Cyc | Action |
|---|---|
| C0 | latch event |
| C1 | format check; RD hash set h(oid) |
| C2 | RD hash set h(noid); old compare -> `hit_old`, way_o, slot (reg) |
| C3 | new compare -> `hit_new`. `!hit_old` -> FAIL_MISSING. `hit_new` -> FAIL_DUP. RD slot[slot_o] |
| C4 | slot data: `rem_o, side, pidx_o`. Select new way: if h(oid)==h(noid) the old way is reusable, else a free way in the new set, else a free stash entry, else FAIL_HASH |
| C5 | RD price old level `{side,pidx_o}`, RD leaf old |
| C6 | RD price new level `{side,pidx_n}`, RD leaf new; leaf old valid |
| C7 | leaf new valid |
| C8 | price old valid (L=3). If same level (`pidx_o==pidx_n`): one level, `q' = q - rem_o + shares`; else `qo' = qo - rem_o` (underflow -> FAIL_QTY_UF), |
| C9 | price new valid: `qn' = qn + shares` (carry -> FAIL_QTY_OVF); new leaf words (with forwarding if same leaf word) |
| C10 | **COMMIT K1**: hash write: invalidate old way (skipped if the way is reused); price write old level; leaf write old (if `qo'==0`); L1/L0 old update |
| C11 | **COMMIT K2**: hash write new key/slot; slot write `{valid,side,pidx_n,shares}`; price write new level; leaf write new (if `qn==0` before); L1/L0 new update. Same level: K1 writes nothing, K2 writes the net level |
| C12 | `done`; BBO fast path or search (+10, one side) |

Latency 13 cycles (130 ns), worst case with search 23 cycles (230 ns). The slot index is unchanged, so no stack push/pop. All checks (C3, C4, C8, C9) precede K1; K1+K2 is an uninterruptible 2-cycle commit window (no new reads issue, CPU cannot clear the book until `done`). Reset in the window -> book cleared at the next init (§22).
Out-of-window new price: policy as ADD; with drop, the old order is still removed? **No**: under `OOW_POLICY=1` the replace is converted to DELETE(oid) and `BOOK_EXACT<=0`. This is the only consistent choice because the order no longer exists at its old price.

### 16.4 BBO read concurrency and hazards
The CPU never reads LOB memories; it reads the snapshot regs (§18). Single-port structural hazards: each of hash/slot/stack/price/leaf has 1 read port used once per cycle in the tables above (checked line by line); Replace uses price/leaf read ports in C5 and C6 (distinct cycles). VGA reads only its own framebuffer. Sustained throughput (cycles/event): ADD 7, EXEC/CANCEL/DELETE 11, REPLACE 13; +10 search: worst 23 cycles = 4.35 M events/s at 100 MHz [CALC: 100e6/23].

## 17. Atomicity, commit points, fail-stop

- [DD] **Check-then-commit**: all validation reads precede one commit window (1 cycle ADD/EXEC; 2 cycles REPLACE), so failures are side-effect free. An operation is atomic w.r.t. the sequencer and MMIO snapshot (snapshot only when `op_busy=0`) but not w.r.t. power loss/reset in the commit window.
- On any failure: `book_valid<=0` **in the same cycle as the failure is detected (C3/C4/C8/C9, before any write)**; `fail_code` latched; `evt_rd_en` stops; `intake_halt<=1`; `done` withheld; CPU sees `STATUS.FAIL`.
- Recovery: only CPU `CTRL.CLEAR` (runs the init FSM, §22) then recovery protocol (§19). The failing event is not re-applied silently: `NEXT_SEQ` is not advanced for the failing message, and the recovery reloads the book from the snapshot.
- `book_valid` can only be set by the recovery-complete handshake (§19), never by reset alone.

## 18. MMIO map and CPU integration

**Actual bus [RV: `rtl/cpu/core/sys_bus_interconnect.v`, `docs/system-bus.md`]:** single outstanding transaction; master drives `req_valid, req_write, req_addr, req_wdata, req_wstrb[3:0]` and holds them stable until `rsp_valid` (1-cycle pulse) with `rsp_rdata`; unmapped address gives `rsp_error` after 1 cycle. The interconnect has **no slot for the LOB**: only `addr[31:28]` = 0, 2, F decoded. Required change (later RTL task, not done here): add `sel_lob = (addr[31:12]==20'h40000)`, a `lob_*` slave port, `SEL_LOB` in `slave_sel`, and response mux inputs `lob_rsp_valid/lob_rsp_rdata`. The old `docs/mmio.md` also places BBO at `0x4000_0100` and a Synthetic Injector at `0x200`; the task statement proposes BBO at `0x0C..0x1C`. [DD] v7 follows the task offsets and supersedes `mmio.md` for `0x4000_0000..0x4000_0FFF`.

Timing [DD]: every access responds with `rsp_valid` exactly 1 cycle after `req_valid` accepted (registered), never stalled by LOB activity (reads come from snapshot/status registers, no LOB memory read). Writes honour `req_wstrb` per byte; reads ignore it. Unmapped offsets inside the window: `rsp_error=0`, read 0, write ignored [DD]. Bus reset (`reset` active-low in the CPU) clears all MMIO regs to reset values.

| Off | Name | Acc | Reset | Fields |
|---|---|---|---|---|
| 0x00 | CTRL | RW | 0 | [0] ENABLE (intake), [1] CLEAR (W1, self-clear, starts init FSM), [2] SNAP_REQ (W1), [3] REC_MODE, [4] OOW_POLICY, [5] BOOK_EXACT_REQ |
| 0x04 | STATUS | R | 0 | [0] INIT_DONE, [1] BOOK_VALID, [2] FAIL, [3] OP_BUSY, [4] SNAP_VALID, [5] REC_ACTIVE, [6] LINK_UP, [7] BOOK_EXACT, [15:8] FAIL_CODE |
| 0x08 | BBO_GEN | R | 0 | `bbo_gen` (increments per snapshot) |
| 0x0C | BID_PRICE | R | 0 | snapshot: `BASE + pidx*TICK` (raw units) or 0 if `bid_valid=0` |
| 0x10 | BID_QTY | R | 0 | snapshot level shares |
| 0x14 | ASK_PRICE | R | 0 | as BID_PRICE |
| 0x18 | ASK_QTY | R | 0 | |
| 0x1C | BBO_FLAGS | R | 0 | [0] bid_valid, [1] ask_valid |
| 0x20 | PRICE_BASE | RW (ENABLE=0) | 0 | raw units |
| 0x24 | TICK | RW (ENABLE=0) | 1 | raw units (0 treated as 1) |
| 0x28 | LOCATE | RW (ENABLE=0) | 0 | [15:0] |
| 0x2C | NEXT_SEQ_LO | RW (ENABLE=0) | 0 | next expected Mold sequence [31:0] |
| 0x30 | NEXT_SEQ_HI | RW | 0 | [63:32] (write LO last: LO write latches both) |
| 0x34..0x4C | SESSION[9:0], MAC/IP/PORT config | RW (ENABLE=0) | 0 | |
| 0x80.. | COUNTERS (R, 32-bit, saturating): ETH_FRAMES, RX_ERR, FCS_BAD, RUNT_GIANT, NOBUF_DROP, MAC_FILT, IP_BAD, UDP_BAD, MOLD_BAD, ITCH_BAD, ITCH_UNSUP, ITCH_FILT, SEQ_GAP, SEQ_DUP, EVT_FIFO_OVF, EVT_ADD/EXEC/CANCEL/DELETE/REPLACE, MISS_ID_IGN, LOB_FAIL, REC_RESTART, OOW_DROP | RW1C via CTRL.CLEAR |

**Coherent BBO read:** CPU writes `SNAP_REQ`; LOB copies live BBO into snapshot regs in one cycle when `OP_BUSY=0` (at most one op, <=23 cycles, later), sets `SNAP_VALID` and `BBO_GEN++`; CPU polls `SNAP_VALID`, reads 0x0C-0x1C, reads `BBO_GEN` twice (before/after) to detect an intervening re-snapshot. 64-bit reads are split across 32-bit regs and are coherent because snapshot regs change only on `SNAP_REQ`. Counters are not snapshot-coherent across regs (documented).
CPU never blocks the LOB: no arbitration on any LOB RAM port.

## 19. Snapshot recovery and sequence reconciliation (P0-G)

**Definition [DD, consistent with MoldUDP64 [PS]]:** `NEXT_SEQ` = sequence number of the next ITCH message the book must apply. The book state `B(k)` = result of applying messages with sequence < k. Heartbeats/EOS carry the next-expected number [PS]; a packet with (S,C) carries messages S..S+C-1 [PS] (sequence numbers are per message, not per packet).

Packet rule in `LIVE`, with (S,C):
- `S == NEXT_SEQ`: accept; after the full packet applies, `NEXT_SEQ = S+C`.
- `S+C <= NEXT_SEQ` (including heartbeat S<NEXT_SEQ, C=0 handled below): duplicate/old: drop, `SEQ_DUP++`.
- `S < NEXT_SEQ < S+C`: overlap; apply only messages with seq >= NEXT_SEQ (skip first `NEXT_SEQ-S` blocks). Counter `SEQ_OVERLAP`.
- `S > NEXT_SEQ`: gap. `book_valid<=0`, `SEQ_GAP++`, enter RECOVER.
- Heartbeat (C=0): `S == NEXT_SEQ` ok; `S > NEXT_SEQ` gap; `S < NEXT_SEQ` ignore. EOS (0xFFFF): same checks, then `STATUS.EOS`, intake halts.
To keep the event FIFO consistent, the parser updates `NEXT_SEQ` per packet at pass-2 completion, and the LOB's applied count is tracked separately (`APPLIED_SEQ`, equal after the FIFO drains).

**Snapshot semantics [UNV, B1].** GLIMPSE delivers the book state followed by an End-of-Snapshot message carrying the sequence number of the last ITCH message reflected (NASDAQ states GLIMPSE gives "current state of the book retransmissions" and the FPGA feed keeps the same message order as the software feed [PS: ITCH 5.0 intro]). Whether the End-of-Snapshot sequence equals the last applied message (`L`) or next (`L+1`) was NOT read (GLIMPSE spec unavailable). v7 defines parameter `GL_CLOSE` and treats `NEXT_SEQ_after = GL_SEQ + 1` assuming last-applied; **unresolved, must be confirmed against the GLIMPSE specification before implementation.**

**Architecture (bounded, fail-closed).** The FPGA has no TCP stack [B2]. The snapshot is obtained by the host PC/CPU and **injected as synthetic canonical events** through a CPU-writable `INJ_*` register set (not in the memory map above; future work, B2). The live UDP stream during recovery is *not buffered in hardware beyond the event FIFO*; instead:
1. Gap -> RECOVER: `book_valid=0`, parser keeps validating packets but drops (not queues) all events; records `LIVE_SEQ_MAX` = highest `S+C` seen.
2. CPU sets `REC_MODE`, runs CLEAR, loads the snapshot via injection, gets `GL_SEQ`, writes `NEXT_SEQ = GL_SEQ+1`, sets `ENABLE`.
3. Parser resumes: the first accepted packet must have `S <= NEXT_SEQ < S+C` or `S == NEXT_SEQ` (overlap handled above). A packet with `S > NEXT_SEQ` means the live feed passed the snapshot: **the snapshot is stale -> `REC_RESTART++`, back to step 1** (no retransmission request is possible: the FPGA has no TX; the host supplies a replay via unicast to the same port as a MoldUDP64 retransmission [DD]).
4. A second gap during recovery -> same restart. `BOOK_VALID<=1` is set by hardware only when `REC_MODE=1`, snapshot-load finished (`SNAP_DONE` from CPU), FIFO drained, and the first live packet has been applied with continuity (`APPLIED_SEQ+1 == NEXT_SEQ`).
Buffer bound [CALC]: the 512-entry event FIFO plus 2 packet banks absorb at most ~512+2*38 events ~ 590 events; wire-rate Add traffic (§20) fills this in ~4 ms of sustained 148k-pkt/s min-frame flood at worst, so hardware live-buffering across a snapshot load (>= tens of ms) is **not possible**; the design therefore depends on an upstream replay contract (B3): the host must replay the stream starting at or before `GL_SEQ+1` after the load. Not proven.

**Worked examples (NEXT_SEQ = N).**
| Case | Packet (S,C) | N before | Result |
|---|---|---|---|
| In order | (100,3), N=100 | 100 | apply 100,101,102, N=103 |
| Duplicate | (100,3), N=103 | 103 | drop |
| Overlap | (101,5), N=103 | 103 | skip 101,102; apply 103..105; N=106 |
| Gap | (110,2), N=106 | 106 | gap, book_valid=0, RECOVER |
| Snapshot GL_SEQ=205 (last-applied assumption) | N=206; packet (200,10) | 206 | overlap: skip 200..205, apply 206..209, N=210 |
| Stale snapshot | N=206, first packet (250,4) | 206 | S>N: restart |
| Heartbeat | (210,0), N=210 | 210 | ok; (230,0) -> gap |
| Second gap | during step 3 | | restart |
| Boundary exact | N=206, packet (206,1) | | apply, valid |
If `GL_CLOSE` is actually next-sequence, set `NEXT_SEQ=GL_SEQ` (one parameter change); incorrect choice would lose or duplicate one message: this is the exact risk B1 holds open.

## 20. Throughput and buffering analysis

Wire [CALC]: per frame, bits = (8 preamble+SFD + L + 12 IFG) x 8, L = frame bytes incl. FCS, at 1e8 b/s.

| Frame L | Time | Frames/s |
|---|---|---|
| 64 B (min) | (8+64+12)x8 = 672 b = 6.72 us | 148,810 |
| 1518 B | (8+1518+12)x8 = 12,304 b = 123.04 us | 8,127 |

Message packing [CALC]: Eth14+IP20+UDP8+Mold20 = 62 B overhead before ITCH blocks. Min-size 64 B frame carries payload 46 B incl. padding -> at most 1 block (2+19) D (or 2+23 X): 1 event/frame -> worst arrival **148,810 events/s** (min frame, delete). Max frame: 1518-4-62 = 1452 B of blocks. With 21 B blocks (D) that is 69 events per 123.04 us frame = **560.8k events/s** peak. With 38 B blocks (A) it is 38 events/frame = 308.8k/s. [CALC] The v5 figure of 1.4 M events/s is not reachable on 100 Mbps Ethernet (peak 560.8k/s).

Parser: 1 B per 50 MHz clock = 20 ns/B; a 21 B block takes 22 clk = 440 ns -> 2.27 M msgs/s > 560.8k. OK (4.05x margin).
LOB service [CALC from §16]: ADD 70 ns (14.3 M/s), EXEC/CANCEL/DELETE 110 ns (9.09 M/s), REPLACE 130 ns, worst 230 ns (4.35 M/s). Worst-case sustained service 4.35 M/s vs arrival 560.8k/s -> utilisation 12.9% worst; the v5 "6.4x" figure is replaced by **7.8x** worst-case (4.35M / 0.5608M) [CALC], contingent on `clk_core=100 MHz` (B5).
FIFO backlog: the parser emits at most one event per 440 ns (21 B block), while the LOB drains one in <= 230 ns, so the FIFO occupancy stays <= 1-2 events in normal operation [CALC]. The FIFO and packet banks fill only when the LOB stalls (fail-stop halts intake). Then the 512-entry FIFO fills in <= 512 x 440 ns = 225 us, the two banks hold <= 2 frames, further frames drop (`NOBUF_DROP`) and surface as a Mold gap -> recovery. All drops are counted; none are silent.

## 21. VGA framebuffer (P0-H)

v5's "1Kx32 write / 32Kx1 read" mapping is replaced. [DD] 320x240, 1 bit/pixel, shown pixel-doubled in 640x480@60 Hz timing (clk_vga ~25.175 MHz: 800x525 total). Logical 76,800 x 1.
- Physical: 3 x RAMB36E1 as 32Kx1 in TDP mode, depth-split across 3 blocks (76,800 > 65,536 so 3 blocks = 98,304 b; 2-bit block select `addr[16:15]`). Both ports are x1, so no asymmetric-width question arises. Port A (write, clk_core): `we`, address `y*320+x` (17 b) computed by the writer; block = addr / 32768 (3 blocks, 15-bit offset), din 1 b. Port B (read, clk_vga): same x1 width, `addr_v = (vy>>1)*320 + (vx>>1)`, read latency 1 (+1 registered 3:1 block mux). Pixel pipeline delayed 2 clocks relative to sync generation.
- Write ownership: only the display writer (CPU MMIO window or LOB depth renderer) writes port A; the VGA reads only port B. A simultaneous read/write to the same address from different clocks gives undefined read data for that pixel [UG473 conflict rules]; accepted visual artefact (one pixel for one frame).
- Color: 1 bpp mapped to Nexys A7 12-bit VGA by replicating the pixel onto all channels; the VGA pins are not constrained in the repo's XDC [RV].
- Reset: BRAM clears only via the bitstream INIT; a clear-screen FSM writes 76,800 zeros (needs 76.8k clk_core cycles = 0.77 ms).
- Alternative if 640x480x1 is wanted: 10 RAMB36 (32Kx1 x 10); not selected. The VGA framebuffer is optional and deferred; the LOB path does not depend on it.

## 22. Initialization, reset, and clearing

Power-on: (1) bitstream configures; BRAM = INIT zero. (2) MMCM LOCKED -> per-domain reset release (§6). (3) `lob_init` FSM (clk_core), after both remote `reset_done`:
- stack: for i in 0..2047 write `stack[i]=i` (2048 cycles), `sp<=2048`;
- hash ways: write zero to sets 0..1023 on all 8 ways (1024 cycles, parallel);
- slot table: write zero to 0..2047 (2048 cycles, parallel with the above);
- price RAM: write zero to 0..16383 (16,384 cycles); leaf RAMs: 256 cycles; L1/L0 FFs and stash cleared in 1 cycle;
Total init = 16,384 + 8 cycles ~ 164 us at 100 MHz [CALC] (price RAM dominates, others run in parallel).
Before `INIT_DONE=1`: parser's `evt_ready=0`, `ENABLE` writes ignored, `book_valid=0`. After INIT: `INIT_DONE=1` (STATUS), `book_valid` still 0. **`book_valid<=1` happens only when** `ENABLE=1` and `REC_MODE` recovery complete, or an explicit CPU `SET_VALID` after a known-empty start (session start, `NEXT_SEQ` = 1 and first packet S=1); reset itself never sets it.
Runtime clear: CPU `CLEAR` -> `ENABLE=0` observed, wait `OP_BUSY=0`, drain/flush the FIFO (async FIFO reset only with both domains' reset asserted per UG473 requirements [UNV details]), run `lob_init`. The packet parser is held with `evt_ready=0`; CPU readiness is independent (the 1 Hz/100 MHz question B5).

## 23. Verification plan (proposed; **no LOB tests executed**)

Reference model: Python (or C) golden book (dict oid -> (side,price,shares), per-level sums, BBO) fed the same events; compare after every event and at each BBO snapshot. SVA invariants I1-I5 (§11).
| Area | Tests (directed + random) |
|---|---|
| CPU/bus | existing `tb_cpu_core.v`; add LOB slave decode, wstrb, error response, reset mid-transaction |
| CDC/reset | async FIFO random-clock-ratio, reset in each domain, handshake data-stable assertions |
| Ethernet | frames from pcap: good, bad FCS, runt, giant, RXER, truncated dibit, back-to-back at IFG |
| IPv4/UDP/Mold/ITCH | each reject case in §9, multi-message packets, length sums wrong, session mismatch, unsupported types |
| Event schema | reserved bits set, illegal op, wrong ver, zero shares |
| LOB ops | A/F/E/C/X/D/U on random books; duplicate, missing, slot exhaustion (2049th add), hash/stash exhaustion with crafted colliding IDs (17 same-set), qty overflow, underflow, Replace same-level/different-level/same-set/different-set, OOW |
| Occupancy/BBO | random add/remove to empty, bests at group/word boundaries, empty book, search latency count = 10 |
| Concurrency | SNAP_REQ during op, BBO_GEN double-read |
| Recovery | each worked example in §19, gap during recovery, stale snapshot |
| Overflow | stalled LOB: FIFO full, banks full, counters match injected drops |
| Throughput | 560.8k ev/s D flood for >=10 s sim time, cycle counts per op equal §16 |
| Synthesis/STA | Vivado utilization vs §15; WNS >= 0 at 100/50/25.175 MHz; CDC report with no unwaived |

## 24. Acceptance criteria

| ID | Criterion | Method |
|---|---|---|
| AC1 | Golden-model mismatches = 0 over >= 1e7 random events | sim |
| AC2 | ADD <=7, EXEC/CAN/DEL <=11, REPLACE <=13 cycles without search; search +10 | sim cycle counter |
| AC3 | Every failure: `book_valid` low before any RAM write of that op, 0 writes | SVA |
| AC4 | No silent drops: sum of counters equals injected-loss count | sim |
| AC5 | Utilization after synth: RAMB36 <= 70/135 (budget headroom over 56) | Vivado |
| AC6 | Post-route WNS >= 0 for clk_core 100 MHz, WHS >= 0 | Vivado |
| AC7 | `report_cdc` clean | Vivado |
| AC8 | `INIT_DONE` after <= 20,000 core cycles | sim |

## 25. Risk register and roadmap

| Risk | Impact | Mitigation |
|---|---|---|
| R1 B1 GLIMPSE semantics | lose/duplicate 1 message | obtain GLIMPSE spec; param `GL_CLOSE` |
| R2 hash adversarial IDs | fail-stop | real-feed trace test; stash size 16 if needed (LUTs) |
| R3 ETH_REFCLK direction | no link | read Nexys schematic first |
| R4 100 MHz CPU not proven | integration | clock-enable instead of divided clock; STA |
| R5 price RAM routing | timing | 16:1 registered mux; fallback 8,192 levels |
| R6 no snapshot path | recovery impossible | CPU injection + host replay |
Roadmap: (1) resolve B1/B4 from primary docs; (2) golden model + parser/ITCH-to-event RTL; (3) LOB RTL with SVA; (4) Ethernet/RMII; (5) recovery; (6) VGA last.

## 26. Independent consistency audit and traceability

Checks performed by reading this document (not by tools): hash 8 ways x 1024 sets, index 10 b matches §12 hash; slot 11-bit addresses cover 2048; price addr 14 b = 1 + 13; leaf word `pidx[12:5]` 8 b = 256 words; L1 `{g,j}` 3+5 = 8 b; schedule latencies use L = 1/1/1/1/3 as in §13/15; each ADD/EXEC cycle uses each single-read RAM once; 2048 slots = 2048 stack entries = 2048 orders (consistent with §12 N). 111 RAMB18 sum: 40+3+2+32+2+8+2+6+8+8 = 111. [CALC]
Known weaknesses: FIFO36E1 mapping and RMII end-of-frame behaviour are [UNV]; no tool verified any of these.

| v5 blocker | v7 resolution | Evidence | Verification | Status |
|---|---|---|---|---|
| P0-A price | window index, 8192 ticks, oow policy | ITCH 5.0 PDF | directed price tests | Resolved on paper |
| P0-B event | 256 b v1, compound Replace | ITCH PDF | schema tests | Resolved on paper |
| P0-C LOB | 1024x8 hash + stash 8, LIFO, fail-stop | Poisson [CALC] | collision tests | Open (B6, probabilistic) |
| P0-D occupancy | 3-level, 10-cycle search | design | BBO tests | Resolved on paper |
| P0-E BRAM | 111 RAMB18 analytical | UG473 modes | Vivado | Open (unsynthesized) |
| P0-F schedules | §16 tables | design | cycle SVA | Resolved on paper |
| P0-G recovery | invariant + examples; GLIMPSE and buffering not proven | Mold PDF | sim | **Open (B1,B2,B3)** |
| P0-H VGA | 320x240x1, 3 x 32Kx1 | UG473 | sim | Resolved on paper |

## 27. Final readiness verdict

**NOT READY** for full LOB RTL implementation. Open: B1 GLIMPSE closing sequence (spec unread), B2 no snapshot transport/TX path, B3 recovery buffering depends on host replay, B4 PHY clock strap unverified, B5 CPU 100 MHz unverified (design currently 1 Hz), B6 hash capacity probabilistic, B7 zero synthesis/P&R evidence. The deterministic LOB core (§10-17) may proceed to a design review and to model-first implementation, but Ethernet/RMII and recovery RTL must wait on B1, B3, B4.
