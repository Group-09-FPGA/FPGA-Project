# Chapter 3: The network front end

Files: `rtl/ethernet/rmii_rx.v`, `rtl/network/net_parser.v`,
`rtl/network/moldudp64_decoder.v`, `rtl/itch/itch_decoder.v`, and the wrapper
`rtl/network/net_ingest.v`. Everything here except the last FIFO runs in the
`eth` clock domain.

## The layers (a letter inside an envelope inside a box)

```
Ethernet frame      [dest MAC | src MAC | type | ............ | CRC]
  IPv4 packet                                 [IP header | ...........]
    UDP datagram                                          [UDP hdr | payload]
      MoldUDP64 packet                                             [session | seq | count | msg, msg, ...]
        ITCH message                                                                      [type 'A' | ... ]
```

Each module peels exactly one layer and hands the inside to the next one.

## `rmii_rx`: bits from the wire to a checked frame

**Job:** assemble bytes from the PHY's 2-bit RMII signals, check the frame is
intact, and hold it in a buffer for the parser.

**Why it is here:** instantiated as `u_rmii_rx` in `net_ingest`. The PHY chip gives
only 2 data bits per clock (`rmii_rxd[1:0]`), a "carrier/data valid" line
(`rmii_crs_dv`) and an error line.

**Analogy:** a receptionist who writes down each caller's message letter by
letter, checks the message's checksum at the end, and only passes it on if it
is correct and a sensible length.

**Key signals**

| Signal | Meaning |
| --- | --- |
| `state` | `RX_IDLE → RX_PREAMBLE → RX_SFD → RX_DATA → RX_CHECK_FCS`, or `RX_DISCARD` |
| `dibit_cnt`, `shift_byte` | assemble four 2-bit pieces into one byte (LSB first) |
| `crc32_reg` | running CRC-32 over the frame |
| `wr_ptr`, `rd_ptr`, `frame_mem` | ring buffer of 2048 bytes; `wr_start_ptr` remembers where the current frame began so a bad frame can be rolled back |
| `frame_valid`, `frame_len` | a complete good frame is ready (length excludes the 4-byte CRC) |
| `frame_read_en`, `frame_byte_out`, `frame_byte_last` | parser pulls bytes out of the buffer |
| `queued_valid` | a second good frame can wait behind the first |
| `cnt_*` | counters: frames, CRC errors, length errors, PHY errors, overflow |

**The main always block (`RX_*` state machine)**

1. *Idle:* wait for carrier.
2. *Preamble/SFD:* the sender transmits `0x55 0x55 ... 0xD5`; when the `0xD5` start-of-frame byte
   is seen, data begins.
3. *Data:* every 4th dibit completes a byte; update the CRC, write the byte into
   `frame_mem`, count it. If `crs_dv` has been low for 2 cycles, the frame ended.
4. *Check:* reject (and roll the write pointer back) if the PHY flagged an error, the
   buffer overflowed, the length is outside 64..1518 bytes, or the CRC residue is not
   `0xDEBB20E3` (the standard "all good" remainder for Ethernet CRC-32). Otherwise
   commit it: `cnt_rx_frames` increments and `frame_valid` rises (or the frame queues
   behind one still being read).

A small second block of the always logic handles reading: when the parser consumes the last
byte (`frame_byte_last`), the next queued frame (if any) becomes current.

**Example:** 142 bytes arrive including the 4-byte CRC → the length check passes (≥ 64), the CRC check passes, `frame_len` = 138 (CRC excluded), `cnt_rx_frames` goes up by 1.

## `net_parser`: Ethernet + IPv4 + UDP

**Job:** read the headers, validate them, and output only the UDP payload.

**Why here:** `u_net_parser` in `net_ingest`. It has the knowledge of header byte
positions (Ethernet = 14 bytes, IPv4 = 20, UDP = 8, so the UDP payload starts at byte 42).

**Analogy:** a customs officer who opens the box, checks the stamps on each wrapper, and only forwards
the letter if every stamp is valid.

**States:** `ST_IDLE → ST_ETH_HEADER → ST_IPV4_HEADER → ST_UDP_HEADER → ST_STREAM_UDP`,
then either `ST_REPLAY_UDP` (good) or `ST_IDLE`/`ST_DRAIN_*` (bad or padding).

**What it checks**

- EtherType is IPv4; IP version 4 and header length 5; not a fragment; protocol is UDP.
- **IPv4 header checksum:** it adds all 16-bit words of the header; the folded sum must be zero.
- Destination UDP port equals the configured port (10443).
- UDP length is consistent with the IP total length and the frame length.
- **UDP checksum** over the pseudo-header and payload (a zero checksum is allowed by the standard).

**The clever part: store, check, then replay.** The payload bytes are written to `payload_mem`
(1472 bytes) *while* the checksum is being computed. Only after the final checksum is
good does the state machine enter `ST_REPLAY_UDP` and read them out as
`udp_payload_valid/byte/start/last`. A corrupted packet therefore never reaches the order book.

**Key signals:** `byte_idx` (position in frame), `csum_acc`/`udp_sum` (running checksums),
`replay_idx`, and the output handshake `udp_payload_valid/ready`, with `start` and `last`
marking the first and last byte of the payload.

**Counters:** `cnt_udp_packets`, `cnt_ip_csum_err`, `cnt_udp_csum_err`, `cnt_udp_len_err`,
plus drop counters (non-IPv4, fragments, non-UDP, wrong port).

## `moldudp64_decoder`: sequence numbers and message framing

**Job:** read the MoldUDP64 header and split the packet into individual ITCH messages;
guard against lost messages.

**Why here:** `u_mold_decoder` in `net_ingest`. A MoldUDP64 packet is
`[10-byte session][8-byte sequence][2-byte message count]` followed by that many
`[2-byte length][message bytes]` records.

**Analogy:** a numbered-page checker for a binder. If page 7 arrives after page 5, a
page is missing, and since the book can't be repaired by skipping, it raises an alarm.

**States:** `MOLD_IDLE → MOLD_HEADER → MOLD_MSG_LEN → MOLD_STREAM_MSG` (or `MOLD_DRAIN`).

**Behaviour**

- Heartbeat (count 0) and end-of-session (count `0xFFFF`) are recognised and counted.
- Normal packet: its sequence number must equal `expected_seq`. If so, messages stream
  out; `expected_seq` advances by the message count. If the sequence is **higher**
  than expected: `seq_gap_detected` pulses (a sticky feed loss in `net_ingest`).
  Lower: a duplicate and ignored.
- `cnt_mold_trunc` counts packets that promise more bytes than they contain.

**Outputs:** `itch_msg_valid/byte/len/seq/start/last/ready`, one message at a time.

## `itch_decoder`: the stock-exchange message to a canonical event

**Job:** collect one ITCH message, decide what it is, and build the 256-bit canonical event.

**Why here:** `u_itch_decoder` in `net_ingest`. Its output is what every later block understands.

**Analogy:** a translator who takes a letter in the exchange's dialect and writes it on the
house's standard form.

**State machine:** `COLLECT → DECODE → (DIVIDE →) SEND`.

- **COLLECT:** copy bytes into `msg_buffer` (48 bytes max) until `itch_msg_last`.
- **DECODE:** look at `msg_buffer[0]`:
  `A`/`F` add (36/40 bytes), `E`/`C` execute (31/36), `X` cancel (23), `D` delete (19),
  `U` replace (35). It checks the length exactly matches (else `decode_error`), that the
  stock locate equals the configured one (else the message is *filtered*, counted, and dropped),
  and that the side byte is `B` or `S`. Other types (administrative messages) are counted and ignored.
- **DIVIDE:** for messages with a price, compute the price index = `(price − base) / tick` using a
  32-step restoring divider (`dividend`, `divisor`, `quotient`, `remainder`, `steps`). If the price
  is below the base, has a remainder (not on a tick), or the index is ≥ 8192, set the
  **out-of-window** bit (`canon_event_data[66]`); the order book will then reject it.
- **SEND:** hold `canon_event_valid` until `canon_event_ready` (the FIFO accepts).

**Counters:** `cnt_itch_total_msgs`, `cnt_itch_order_events`, `cnt_itch_filtered_msgs`, `cnt_itch_admin_msgs`,
`cnt_itch_oow_events`.

**Example:** an `A` message "buy 300 @ 90.5000, id 0x2001" with base 900000 (=$90.0000) and tick 1000
(=$0.1000): `(905000 − 900000) / 1000 = 5`, remainder 0, so the event carries price index 5 and OOW = 0.

## `net_ingest`: the wrapper that ties it together

**Job:** one block that goes from Ethernet pins to a core-domain event stream plus statistics.

**Why it exists:** before the refactor all of this lived in `top_system`. It now hides the
`eth` domain: its inputs are the PHY pins and a configuration word from the core;
its outputs are all in the `core` domain.

**What is inside beyond the four modules above**

| Item | Purpose |
| --- | --- |
| `u_cfg_cdc` | Carries `{locate, price_base, tick}` from `core` to `eth` (the decoder needs them). Its `src_ready` becomes `cfg_ready`, which the CPU firmware waits on (STATUS bit 7). |
| `u_event_fifo` | The 64-entry event FIFO from `eth` to `core`. |
| `u_fifo_events` | Counts events accepted into the FIFO. |
| `feed_loss_eth` + `loss_sync1/2` | **Sticky** feed-loss flag. Set by a sequence gap, decode error, FIFO overflow, **any** CRC/length/PHY/overflow/truncation/checksum error, or a configuration change after messages arrived. Crosses into `core` through two flops and becomes `feed_loss`, which makes `lob_core` fail-stop. |
| `u_diag_cdc`, `u_ip_csum_cdc`, `u_pipe_cdc` | Snapshot the counters into the `core` domain as `diag` (352 bits), `ip_csum_errors`, and `pipe_stats` (160 bits). |

**Why a sticky flag?** Once any frame or message may have been lost, the book can no longer be
trusted. So loss is latched until reset, and the firmware/hardware requires a replay from sequence 1.

**Key outputs**

| Output | Meaning |
| --- | --- |
| `evt_valid/data/ready` | the canonical event stream (core domain) |
| `feed_loss` | sticky, stops the order book |
| `diag[351:0]` | `{rx_frames, crc_err, mold_msgs, seq_gaps, len_err, phy_err, overflow, mold_trunc, udp_len_err, udp_csum_err, ...flags}`; read by the CPU (`net_mmio_slave`), LEDs and UART |
| `pipe_stats[159:0]` | `{rx_frames, udp_packets, mold_msgs, itch_events, fifo_events}` for the UART status line |
