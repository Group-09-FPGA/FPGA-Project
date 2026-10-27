# Parser and limit order book hardware

## 1. Parser: Ethernet bytes to order events

### RMII receiver (`rmii_rx`)

The receiver assembles the PHY's two-bit RMII samples into bytes, recognizes Ethernet frame boundaries, and checks frame length and CRC-32. A block-RAM frame buffer holds a complete frame before the next module reads it; counters record accepted frames and receive errors.

### Ethernet, IPv4, and UDP parser (`net_parser`)

A hardware state machine walks through the Ethernet, IPv4, and UDP headers and selects packets addressed to the configured destination and UDP port 10443. It checks lengths and checksums, then streams only the UDP payload onward; its payload buffer is inferred as block RAM.

### MoldUDP64 decoder (`moldudp64_decoder`)

This state machine reads the Mold session ID, sequence number, message count, and each length-prefixed ITCH message. A 64-bit expected-sequence register detects gaps or duplicates, while byte counters mark message starts and ends for the ITCH decoder.

### ITCH decoder (`itch_decoder`)

The decoder buffers one message, checks its type, length, and stock locate, and converts supported `A`, `F`, `E`, `C`, `X`, `D`, and `U` messages into the same 256-bit event format. Hardware registers and a sequential divider convert prices into price-level indexes before the event is released.

### Dual-clock event FIFO (`async_event_fifo`)

The FIFO queues decoded 256-bit events between the Ethernet and LOB clock domains, each running at 50 MHz. Separate read and write pointers with clock-domain synchronization provide safe handoff and backpressure; this top-level instance has 64 entries.

## 2. Actual LOB: order events to best bid and ask

### Event validator (`lob_event_decoder`)

Combinational checks validate the event version, operation, reserved bits, order IDs, share count, and price fields. Invalid events produce an error code before the book's storage is changed.

### LOB controller (`lob_core`)

A clocked state machine coordinates order lookup, slot allocation, quantity updates, price-level updates, and best-price refresh for each event. It asserts completion only after the update commits and uses fail-stop status if it detects an invalid event or feed fault.

### Order-ID hash table (`lob_hash_table`)

The hash table maps a 64-bit order ID to a slot number, so an execution, cancellation, deletion, or replacement can find its stored order. It uses 1,024 sets with eight block-RAM ways per set and a small eight-entry collision stash.

### Order slot table (`lob_slot_table`)

The slot table stores the active orders' side, price-level index, and remaining share quantity in 2,048 entries of 47 bits each. A synchronous block-RAM read provides the existing order data before the controller decides how to update it.

### Free list (`lob_free_list`)

The free list supplies an unused slot when an order is added and takes the slot back when an order is removed. It is implemented as a 2,048-entry block-RAM stack with a stack pointer that also tracks free and active capacity.

### Price-level RAM (`lob_price_ram`)

This memory stores the total share quantity at each of 8,192 bid and 8,192 ask price levels, for 16,384 levels of 32 bits each. The controller updates a level when shares are added or removed, and a pipelined block-RAM read returns the previous total.

### Occupancy tree (`lob_occupancy`)

The occupancy tree marks which price levels currently contain shares, using distributed-RAM leaf bitmaps and register masks above them. Its priority-search state machine finds the highest occupied bid or lowest occupied ask when the current best level becomes empty.

### Best bid and offer unit (`lob_bbo`)

The BBO unit keeps the current best bid and ask price levels and their aggregate quantities in registers. It accepts direct updates when the best level changes in place, or a result from the occupancy search when a best level disappears, then computes the displayed prices from the configured base and tick.
