# Owner 1: Network in, clocks and clock crossings  (difficulty: medium)

## Your 30-second pitch

> "I own everything between the Ethernet cable and the point where an order event is
> ready for the order book. I receive Ethernet frames, check them, peel off the IP,
> UDP and MoldUDP64 layers, decode the ITCH message into a 256-bit canonical event,
> and carry it safely into the core clock. I also own all the clocks, the resets,
> and the two modules that move data between clock domains, which every other
> part of the project uses."

## Your modules

| Module | File | Lines | One-line job |
| --- | --- | --- | --- |
| `rmii_rx` | `rtl/ethernet/rmii_rx.v` | 322 | PHY bits → checked Ethernet frames in a buffer |
| `net_parser` | `rtl/network/net_parser.v` | 365 | Ethernet + IPv4 + UDP headers; checksums; payload store and replay |
| `moldudp64_decoder` | `rtl/network/moldudp64_decoder.v` | 299 | Session / sequence tracking; splits the packet into messages |
| `itch_decoder` | `rtl/itch/itch_decoder.v` | 184 | ITCH message → 256-bit canonical event (price index divide) |
| `net_ingest` | `rtl/network/net_ingest.v` | ~160 | Wrapper: the four above + FIFO + loss flag + counter crossings |
| `clk_rst_mgr` | `rtl/clocking/clk_rst_mgr.v` | 178 | 100 MHz → project clocks; resets; PHY power-up reset |
| `phy_refclk_out` | `rtl/clocking/phy_refclk_out.v` | 20 | puts the 50 MHz clock on the PHY's pin |
| `config_cdc` | `rtl/common/config_cdc.v` | 59 | multi-bit snapshot crossing (hold + handshake) |
| `async_event_fifo` | `rtl/common/async_event_fifo.v` | 199 | queue between two clocks (Gray pointers) |
| `event_counter` | `rtl/common/event_counter.v` | 14 | counts cycles where `inc` is high |

## Tests you can run live

```bash
# from the repo root; copy the exact commands from sim/run_ci_tests.sh
tb_rmii_rx          # frames, CRC, runts, PHY errors
tb_rmii_rx_queue    # ring buffer wrap and a queued second frame
tb_net_parser_padding / tb_net_parser_max_payload
tb_moldudp64_gap    # sequence gap → fail-stop signal
tb_itch_decoder_config
tb_config_cdc
tb_async_event_fifo_wrap
```

## Reading order

1. [00-system-in-10-minutes](../00-system-in-10-minutes.md): the whole system.
2. [01-the-system-from-my-seat](01-the-system-from-my-seat.md): what your part receives, produces, and where it ends up (including on the VGA monitor).
3. [02-rmii-rx](02-rmii-rx.md)
4. [03-net-parser-and-mold](03-net-parser-and-mold.md)
5. [04-itch-decoder-and-ingest](04-itch-decoder-and-ingest.md)
6. [05-clocks-and-crossings](05-clocks-and-crossings.md)
7. [06-viva-qa](06-viva-qa.md): practise answering.

## The five facts you must be able to state without looking

1. The PHY gives **2 bits per 50 MHz clock**; a byte takes 4 clocks.
2. A frame is accepted only if: no PHY error, no buffer overflow, 64–1518 bytes, and **CRC residue = 0xDEBB20E3**.
3. A UDP payload only leaves `net_parser` after its checksum is verified (**store, check, replay**).
4. A MoldUDP64 **sequence gap** (or a session change, or a first packet that is not sequence 1) raises a sticky loss flag that **fail-stops the order book**.
5. The canonical event is **256 bits**; the price becomes an **index** `(price − base) / tick` using a 32-step divider, and a bad price sets the **out-of-window** bit.
