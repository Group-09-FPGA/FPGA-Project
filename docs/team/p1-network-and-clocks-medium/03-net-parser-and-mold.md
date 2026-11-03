# `net_parser` and `moldudp64_decoder`

Both run in the `eth` clock and sit between `rmii_rx` and `itch_decoder` inside `net_ingest`.

```
rmii_rx ──frame bytes──► net_parser ──UDP payload bytes──► moldudp64_decoder ──ITCH message bytes──► itch_decoder
        frame_valid/len/byte/last        udp_payload_valid/start/last/ready          itch_msg_valid/start/last/ready
```

---

# Part A: `net_parser` (`rtl/network/net_parser.v`, 365 lines)

## A1. What it does

Reads one frame byte by byte and checks, layer by layer, that it is an IPv4 + UDP packet for us. If everything
passes, it outputs **only the UDP payload**. If anything fails, it drains the rest of the frame and counts why.

## A2. The layers and their byte positions

A frame, counting from byte 0 (the preamble is already gone; `rmii_rx` removed it):

| Bytes | Field | Notes |
| --- | --- | --- |
| 0-5 | destination MAC | compared with `cfg_dst_mac` (0 = accept any) |
| 6-11 | source MAC | ignored |
| 12-13 | EtherType | must be `0x0800` (IPv4) |
| 14 | IP version (high nibble) / header length (low nibble) | must be 4 and 5 (20-byte header) |
| 16-17 | IP total length | |
| 20-21 | flags + fragment offset | `& 0x3FFF` must be 0 (no fragments) |
| 23 | IP protocol | must be 17 (UDP) |
| 24-25 | IP header checksum | |
| 26-29 | source IP | used in the UDP pseudo-header |
| 30-33 | destination IP | compared with `cfg_dst_ip` (0 = accept any) |
| 34-35 | UDP source port | ignored |
| 36-37 | UDP destination port | must equal 10443 (`cfg_udp_port`) |
| 38-39 | UDP length | header (8) + payload |
| 40-41 | UDP checksum | |
| **42 →** | **UDP payload** | the MoldUDP64 packet |

(`net_ingest` passes `cfg_dst_mac = DEST_MAC` and `cfg_dst_ip = DEST_IP`, both parameters defaulting to 0.)

## A3. The state machine

```
 ST_IDLE ─frame_valid─► ST_ETH_HEADER ─► ST_IPV4_HEADER ─► ST_UDP_HEADER ─► ST_STREAM_UDP ─► (ST_DRAIN_PAD) ─► ST_REPLAY_UDP ─► ST_IDLE
                              │                │                 │                │
                              └────────────────┴────────────────►─┴───────────────►┴──► ST_DRAIN_DROP ─► ST_IDLE   (any check fails)
```

| State | What it does |
| --- | --- |
| `ST_IDLE` | clears `byte_idx`, checksum accumulators; when `frame_valid` rises, go to the Ethernet header |
| `ST_ETH_HEADER` | shifts bytes 0-5 into `dst_mac`; captures the EtherType at bytes 12-13. If `0x0800` and the MAC matches → IPv4 header; else `cnt_non_ipv4_drop++` → drain |
| `ST_IPV4_HEADER` | adds every 16-bit word of the IP header into `csum_acc`; captures version, length, flags, protocol, checksum, destination IP. At byte 33 (end of the header) it makes **four** checks in order: version/IHL/dest-IP → fragment → protocol → length sanity and **IP checksum** (see A4) |
| `ST_UDP_HEADER` | captures ports, length, checksum; adds the header words into the UDP sum; at byte 41 checks the **destination port** and the UDP/IP **length consistency**; if fine, `udp_payload_len = udp_len − 8` |
| `ST_STREAM_UDP` | each byte is written into `payload_mem` and added into the UDP checksum; when the last payload byte arrives it evaluates the **UDP checksum** |
| `ST_DRAIN_PAD` | consumes the **padding** bytes some short frames carry after the UDP payload (Ethernet pads to 60 bytes) until `frame_byte_last` |
| `ST_REPLAY_UDP` | reads `payload_mem` back out as `udp_payload_*` for the next module |
| `ST_DRAIN_DROP` | throws away the rest of a rejected frame until `frame_byte_last` |

`frame_read_en` (the "give me the next byte" signal to `rmii_rx`) is **combinational**: true in the header, stream, and both drain states.

## A4. The two checksums (important and often asked)

The Internet checksum is a **16-bit one's-complement sum**.

```verilog
function [15:0] fold_checksum;
    input [31:0] acc;
    reg [31:0] sum;
    begin
        sum = acc[31:16] + acc[15:0];   // fold the carries back in
        sum = sum + sum[31:16];
        fold_checksum = ~sum[15:0];     // one's complement
    end
endfunction
```

**IPv4 header checksum.** The sender stores the one's complement of the sum of all 16-bit header words
(with the checksum field itself as zero). The receiver adds **all** words **including** the stored checksum:
a correct header gives all ones, so `fold_checksum(...)` returns `0x0000`. The parser checks
`fold_checksum(csum_acc + last_word) != 16'h0000` → `cnt_ip_csum_err++`.

**UDP checksum.** Computed over a **pseudo-header** (source IP, destination IP, protocol 17, UDP length) plus the
UDP header and payload. The parser accumulates:
- `pseudo_acc`: the two IP address words (bytes 26-33),
- `+ 17` (the protocol),
- `udp_sum`: header words, with the UDP length added **twice** (once as the pseudo-header's length field, once as the header's own length field; see `byte_idx == 12'd39` in the code),
- payload words; an odd final byte is padded with a zero low byte (`final_udp_sum`).

A UDP checksum field of `0x0000` means "sender did not compute one" and is accepted. Otherwise a wrong sum
→ `cnt_udp_csum_err++` and the packet is dropped.

## A5. The key design idea: store, check, replay

The checksum is only known **after** the last payload byte. But the bytes must not reach the order book until the
packet is proven good. So:

1. During `ST_STREAM_UDP`, payload bytes are **written into `payload_mem`** (1472 bytes, block RAM; the maximum UDP payload in one frame).
2. At the last byte, `replay_allowed` is computed from the UDP checksum.
3. Only if good: `cnt_udp_packets++` and the FSM enters `ST_REPLAY_UDP`, which **reads the stored bytes back out** with a valid/ready handshake (`udp_payload_valid`, `udp_payload_start`, `udp_payload_last`, `udp_payload_ready`).
4. If bad: nothing is ever sent downstream.

*Analogy:* a mail clerk who photocopies the letter, checks the stamp on the envelope, and only then hands over the
copy; a forged letter never reaches the boss's desk.

The RAM write is in its own `always @(posedge clk)` block with no reset (`if (rst_n && state == ST_STREAM_UDP)`):
keeping the reset out of the memory block lets Vivado infer a block RAM instead of 1472 individual flip-flops.

## A6. Outputs and counters

| Output | Meaning |
| --- | --- |
| `udp_payload_valid/start/last/byte[7:0]/len[11:0]` | the payload stream |
| `udp_payload_ready` (input) | next module accepts |
| `cnt_udp_packets` | good UDP packets (connected in `net_ingest`) |
| `cnt_ipv4_frames`, `cnt_non_ipv4_drop`, `cnt_ip_frag_drop`, `cnt_non_udp_drop`, `cnt_port_mismatch_drop` | debug counters for the named reasons; they exist in the module but are **left unconnected** in `net_ingest` |
| `cnt_ip_csum_err`, `cnt_udp_len_err`, `cnt_udp_csum_err` | errors; these three feed the **sticky feed-loss flag** |

## A7. Worked example

Frame: 142 bytes with FCS → `frame_len = 138`. The Ethernet header (14 bytes) says IPv4; the IP header (20 bytes) has
total length 124 and protocol 17; the UDP header (8 bytes) has destination port 10443 and length 104, so the payload is 96 bytes
(a MoldUDP64 header of 20 bytes + two framed messages). The parser streams 96 bytes into `payload_mem`, finds
the UDP checksum good, and replays those 96 bytes to `moldudp64_decoder`.

## A8. "What if"

- **The destination port is 10444?** `cnt_port_mismatch_drop++`, drain, nothing downstream.
- **A fragment (More-Fragments flag)?** `cnt_ip_frag_drop++`: UDP reassembly is not supported.
- **One payload byte is corrupted but the Ethernet CRC is fine?** (rare, e.g. a bug in a router) the UDP checksum catches it → `cnt_udp_csum_err++` → feed-loss flag.
- **Padding?** A tiny UDP payload ends before the frame does; `ST_DRAIN_PAD` skips the padding.

---

# Part B: `moldudp64_decoder` (`rtl/network/moldudp64_decoder.v`, 299 lines)

## B1. What MoldUDP64 is

A simple framing protocol used for exchange feeds over UDP. One UDP payload = one **packet**:

```
 bytes 0-9    session id        (10 bytes, ASCII name of the feed session)
 bytes 10-17  sequence number   (64-bit, big-endian): number of the FIRST message in this packet
 bytes 18-19  message count     (16-bit)
 then, `count` times:  [2-byte length][message bytes]
```

Special counts: **0 = heartbeat** (no messages), **0xFFFF = end of session**.

Sequence numbers let the receiver detect **lost packets**: if the next packet's sequence is higher than expected, something was lost.

## B2. The state machine

| State | Job |
| --- | --- |
| `MOLD_IDLE` | waits for the first payload byte (`udp_payload_valid && udp_payload_start`) |
| `MOLD_HEADER` | reads 20 header bytes into `session_id`, `pkt_seq`, `msg_count`; at byte 19 it **decides** what to do (see B3) |
| `MOLD_MSG_LEN` | reads the 2-byte length of the next message into `cur_msg_len` |
| `MOLD_STREAM_MSG` | forwards that message's bytes to the ITCH decoder, marking `start` and `last`; after the last message of the packet returns to `MOLD_IDLE` |
| `MOLD_DRAIN` | discards the rest of an ignored packet |

`udp_payload_ready` is `1` in `IDLE`, `HEADER` and `DRAIN` (the decoder always consumes those bytes) and equals `itch_msg_ready` while streaming
(so the ITCH decoder can **apply backpressure**, pausing the whole chain up to `rmii_rx`).

## B3. The decision at the end of the header

When the 20th header byte arrives, the decoder runs this decision tree (this is the heart of the module):

| Check | Result |
| --- | --- |
| a session was already established and `session_id != active_session_id` | **sequence gap**: `seq_gap_detected`, `cnt_seq_gaps++`, record expected vs received, drain |
| `msg_count == 0` | heartbeat: `cnt_heartbeats++`, drain |
| `msg_count == 0xFFFF` | end of session: `cnt_end_of_session++`, drain |
| `seq_gap_detected` is already set | drain (a book with missing messages cannot be repaired by continuing later) |
| first packet (`!seq_initialized`) | must have `pkt_seq == cfg_expected_seq` (**1** in this design); otherwise it is a **gap** |
| `pkt_seq == expected_seq` | in sequence: go to `MOLD_MSG_LEN` |
| `pkt_seq > expected_seq` | **gap** |
| `pkt_seq < expected_seq` | duplicate / stale: `cnt_duplicates++`, drain |

**Consequence worth stating in a viva:** the book can only be valid if the feed starts at **sequence 1** (after a reset the
sender must replay from the beginning). Starting mid-stream is treated as a gap on purpose; an empty book cannot be trusted
if earlier orders are missing.

## B4. Per-message bookkeeping

- Each forwarded message gets `itch_msg_seq = expected_seq` (the transport sequence of *that message*).
- On each message's last byte: `cnt_mold_msgs++` and `expected_seq <= expected_seq + 1`. Sequence advances **per message**, not per packet.
- `cur_msg_idx` counts messages within the packet; when it reaches `msg_count`, the packet is done.
- If the payload ends earlier than the header promised (`udp_payload_last` too soon), `cnt_trunc_errors++` (a **truncation error**; it also feeds the feed-loss flag).

## B5. Signals you should be able to name

| Signal | Meaning |
| --- | --- |
| `seq_gap_detected` | sticky inside the module; also pulses into `net_ingest` as part of the loss logic |
| `gap_expected_seq`, `gap_received_seq` | for diagnosis (not connected up in this project) |
| `expected_seq` | the next message number we want |
| `itch_msg_valid/byte/len/seq/start/last/ready` | the message stream to the ITCH decoder |
| `cnt_mold_pkts`, `cnt_mold_msgs`, `cnt_seq_gaps`, `cnt_trunc_errors` | counters |
| `cfg_seq_reset`, `cfg_expected_seq`, `cfg_seq_override` | recovery controls; `net_ingest` ties them to `0`, `1`, `0` (no override: recovery is by resetting the board) |

## B6. Worked example

Packet: session `"ITCHTEST01"`, sequence **1**, count **2**, then `[0x0024][36-byte Add msg]`, `[0x0024][36-byte Add msg]`.

1. Header: session stored; `seq_initialized` was 0, `pkt_seq (1) == cfg_expected_seq (1)` ✓ → `expected_seq = 1`, go to `MSG_LEN`.
2. Message 1 forwarded with `itch_msg_seq = 1`; at its last byte `expected_seq = 2`, `cnt_mold_msgs = 1`.
3. Message 2 forwarded with `itch_msg_seq = 2`; `expected_seq = 3`, `cnt_mold_msgs = 2`; `cur_msg_idx + 1 == msg_count` → `MOLD_IDLE`.

The next packet must start at sequence **3**. If it starts at 5: `seq_gap_detected`, `cnt_seq_gaps = 1`, drain, and `net_ingest`'s sticky
`feed_loss_eth` becomes 1, which crosses to the core and fail-stops the book.

## B7. "What if"

- **A heartbeat arrives?** Count 0 → `cnt_heartbeats++`, drained, no event.
- **The sender restarts with a different session id?** Treated as a gap → fail-stop; the book would otherwise mix two sessions.
- **Duplicate packet (a router retransmits)?** Ignored (`cnt_duplicates++`), the book is unaffected.
- **The ITCH decoder is slow (still dividing)?** `itch_msg_ready` is low, so `udp_payload_ready` is low, `net_parser` pauses in `ST_REPLAY_UDP`, and the data waits in `payload_mem`. Nothing is lost unless the next frame overruns `rmii_rx`'s queue.
