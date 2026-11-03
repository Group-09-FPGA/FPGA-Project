# Viva questions and model answers (owner 1)

Answer in this order: **what it does → how → what if**. Where a question touches another part,
use the one-line interface from the README.

## A. Basics

**1. Walk me through what happens to one Ethernet frame.**
`rmii_rx` assembles it from 2-bit pieces, checks the CRC and length, and stores it. `net_parser` checks the Ethernet, IPv4 and UDP headers and checksums, storing the
payload and replaying it only if the UDP checksum is good. `moldudp64_decoder` checks the sequence number and splits the payload into messages. `itch_decoder` turns each order
message into a 256-bit event, converting the price to an index. The event passes through an async FIFO into the core clock.

**2. Why does Ethernet RMII use only two data bits?** Reduced pin count. 2 bits × 50 MHz = 100 Mbit/s, so a byte takes four clocks.

**3. How do you know a frame has started?** `crs_dv` rises; the preamble is `01` dibits; the first `11` dibit is the end of the SFD (0xD5, LSB first).

**4. How do you know a frame has ended?** `crs_dv` low for **two consecutive clocks** (the PHY toggles it `1,0,1,0` while draining, so one low clock is not enough).

**5. What does the CRC check do, and why compare to 0xDEBB20E3?** The CRC register runs over the whole frame **including** the 4-byte FCS. For a correct frame the register ends at the constant residue `0xDEBB20E3`; any corruption changes it.

## B. "What if" questions

**6. What if the CRC is wrong?** The frame is dropped, `cnt_crc_err` increments, the write pointer rolls back, and the sticky feed-loss flag is set, which fail-stops the book.

**7. Why does a single bad frame stop the whole book?** It might have contained an add or delete. A book that misses one message shows wrong prices indefinitely, so the design refuses to continue. Recovery is a reset and a replay from sequence 1.

**8. What if a frame is shorter than 64 bytes?** `cnt_len_err++` (a runt); same consequences.

**9. What if the UDP payload is corrupted but the Ethernet CRC is fine?** The UDP checksum fails (`cnt_udp_csum_err`), and since the payload was only *stored* (not forwarded), nothing downstream ever sees it.

**10. What if the destination port is wrong?** `cnt_port_mismatch_drop++`, frame drained, no feed-loss flag: it is not our traffic.
(Careful: the feed-loss flag is raised by *errors*, not by ordinary drops like a wrong port, a fragment, or non-IPv4.)

**11. What if a MoldUDP packet is lost (sequence jumps from 3 to 7)?** `seq_gap_detected`, `cnt_seq_gaps++`, the packet is drained, and the loss flag fail-stops the book.

**12. What if the feed starts at sequence 100?** The first packet must equal `cfg_expected_seq = 1`; otherwise it is a gap. The book is only valid when it has seen the whole history from the start.

**13. What if a duplicate packet arrives?** Lower sequence than expected → `cnt_duplicates++`, ignored, harmless.

**14. What if the price is not a multiple of the tick?** The divider leaves a remainder → OOW bit set → the book rejects it with `FAIL_PRICE_OOW`.

**15. What if the price is below the base price?** `price < base` forces `divisor = 0`; the event is sent with OOW set.

**16. What if the order book is slower than the network?** Backpressure travels back: the FIFO fills, the decoder waits in `SEND`, `itch_msg_ready` is low, `moldudp64_decoder` waits, `net_parser` waits in `ST_REPLAY_UDP`, and finally `rmii_rx` can queue one more frame before dropping and flagging an overflow.

**17. What if the FIFO overflows?** `wr_overflow` pulses and sets the feed-loss flag.

## C. Clocks and crossings

**18. Why are there four clocks?** `eth` for the PHY interface, `core` for the book and CPU, `ui` (25 MHz) for keyboard and display logic, `pixel` (74.25 MHz) for the 720p video.

**19. Why not just use one clock?** The PHY interface and video timing are dictated by external standards (50 MHz, 74.25 MHz); the UI is slow to ease timing. Different frequencies require crossings.

**20. What is metastability?** A flip-flop that samples a signal changing at the same instant can sit between 0 and 1 for a while. A two-flop synchronizer gives it a full clock period to resolve before the value is used.

**21. When do you use `config_cdc` and when `async_event_fifo`?** `config_cdc`: slowly changing multi-bit values where the latest snapshot is enough (counters, config, status). FIFO: streams where every item and its order matter (events).

**22. Why Gray code in the FIFO?** Only one bit changes per count, so a pointer sampled mid-change is old-or-new, never garbage.

**23. How can the FIFO tell full from empty if the pointers are equal in both cases?** The pointers have one extra bit. Equal → empty; equal except the top bit → full (a lap ahead).

**24. Why does `config_cdc` use a toggle, not a pulse?** A pulse can be missed by a slower clock; a level change persists until observed.

**25. What happens if I rename `u_event_fifo`?** The timing exceptions in the XDC match that name. The Gray-pointer paths would lose their `set_max_delay`, and synthesis shows negative slack and critical warnings (this actually happened during the refactor).

**26. Why is reset released through a 4-flop shift register?** So every flop in a domain leaves reset on the same clock edge (synchronous release), while assertion remains immediate.

**27. What is the 1.3 ms counter for?** It holds the PHY in reset after power-up so the Ethernet chip can start cleanly.

## D. Cross-over questions

**28. Where does the event go after the FIFO?** `order_merge` (owner 3) alternates it with keyboard events; `lob_core` executes it on the memories (owners 3 and 2).

**29. How does a keyboard order get into the core clock?** The same `async_event_fifo` module, instantiated as `u_local_fifo`, 4 deep, from the `ui` clock.

**30. How can the VGA monitor show your packet counters?** `net_ingest`'s `diag` and `pipe_stats` are in the core clock; `status_to_ui` crosses them to the UI clock with `config_cdc`; `ui_registers` packs them (words 22-28); the display CPU's firmware draws them on the Status page.

**31. Who tells you the price base and tick?** The CPU (owner 4) through `lob_mmio_slave`; `u_cfg_cdc` carries them to the `eth` clock. If they change after messages arrived, you raise the feed-loss flag.

**32. Does the book work without the CPU?** No: the CPU must write `1` to the LOB `CTRL` register; until then `event_ready` is low and your FIFO just fills (then backpressure builds). Network packets sent before that would eventually overflow and set feed-loss.

## E. Tests

**33. How do you test your part?** `tb_rmii_rx` (good frame, bad CRC, runt, PHY error), `tb_rmii_rx_queue` (ring wrap, queued frame), `tb_net_parser_padding`/`max_payload`, `tb_moldudp64_gap` (gap → fail-stop signal), `tb_itch_decoder_config`, `tb_config_cdc`, `tb_async_event_fifo_wrap`. The full-system `tb_system_top` sends real frames including a bad IP checksum and checks that it invalidates the book.

**34. How do you demo it live?** Copy the `iverilog` command for the testbench from `sim/run_ci_tests.sh` and run it with `vvp`; the output ends with `[PASS]`.
