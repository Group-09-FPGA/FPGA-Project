# System Architecture: Python Limit Order Book Reference Model

This document outlines the software architecture, design principles, module boundaries, and data flow of the Python Limit Order Book (LOB) simulator.

---

## 1. Architectural Principles

1. **Strict Layer Separation**:
   - The core order book logic knows nothing about network sockets, UDP, byte encodings, or terminal rendering.
   - The binary decoder produces normalized internal dataclass events.
   - The transport layer manages packet sequencing and gap detection independently from book mutation.
2. **Deterministic Functional Reference**:
   - For a given initial state and sequence of events, the book produces an identical, bit-exact sequence of states and audit records.
3. **Hardware Correspondence**:
   - Memory models and state transitions mirror future FPGA RTL blocks (FIFO queues, slot indexing, BBO tracking, register snapshots).
4. **Defensive Invariant Validation**:
   - Every mutation can be validated against structural and mathematical invariants. Invalid inputs never partially corrupt the state.

---

## 2. Layered Architecture Diagram

```
+--------------------------------------------------------------------------+
|                         Presentation & Export Layer                      |
|   CLI (cli.py)  |  Terminal Visualizer (vis.py)  | RTL Vector Exporter  |
+--------------------------------------------------------------------------+
                                     ^
                                     | AuditRecords & Snapshots
+--------------------------------------------------------------------------+
|                      Transport & Recovery Layer                          |
|   MoldUDP64 Parser (moldudp64.py)  | Sequence State Machine (recovery.py)|
+--------------------------------------------------------------------------+
                                     |
                                     v ITCH Byte Payloads
+--------------------------------------------------------------------------+
|                       Feed Decoding Layer                                |
|   ITCH 5.0 Binary Decoder (feed_decoder.py)                              |
|   - Big-endian struct unpacker, 48-bit timestamp decoder                 |
+--------------------------------------------------------------------------+
                                     |
                                     v Normalized Events
+--------------------------------------------------------------------------+
|                       Deterministic Core Engine                          |
|   order_book.py  |  price_levels.py  |  statistics.py  |  models.py      |
|   - Order Map (order_id -> Order)                                        |
|   - Bid Price Levels (Sorted Descending)                                 |
|   - Ask Price Levels (Sorted Ascending)                                  |
|   - Fast Top-of-Book (BBO) Tracker                                       |
|   - Audit Record Generator (before/after states, explanation)            |
+--------------------------------------------------------------------------+
                                     ^
                                     | Differential Verification
+--------------------------------------------------------------------------+
|                      Independent Reference Model                         |
|   reference_model.py (Brute-force naive list implementation)             |
+--------------------------------------------------------------------------+
```

---

## 3. Module Responsibilities

### `models.py`
Defines immutable/strongly-typed data structures:
- `Side`: Enum (`BUY`, `SELL`).
- `OrderStatus`: Enum (`ACTIVE`, `PARTIALLY_FILLED`, `FILLED`, `CANCELLED`).
- `Order`: Dataclass (`order_id`, `side`, `price`, `original_qty`, `remaining_qty`, `executed_qty`, `timestamp_ns`, `mpid`).
- `PriceLevelSummary`: Dataclass (`price`, `total_quantity`, `order_count`).
- `TOBSnapshot`: Dataclass (`best_bid_price`, `best_bid_qty`, `best_ask_price`, `best_ask_qty`, `spread`, `midpoint`, `is_locked`, `is_crossed`).
- `BookInvariants`: Dataclass with results of structural integrity checks.

### `price_levels.py`
- `PriceLevel`: Manages a single price tier:
  - Maintains `price`, `total_quantity`, and `order_count`.
  - Maintains a FIFO queue of `Order` objects at this price level.
  - Supports $O(1)$ head/tail operations, order additions, partial reductions, and order removals.

### `order_book.py`
- `OrderBook`: Core book manager:
  - `orders`: Hash map `dict[uint64, Order]` mapping `order_id` directly to `Order`.
  - `bids`: Sorted dictionary / skiplist / binary tree of `PriceLevel` for buy orders (descending price).
  - `asks`: Sorted dictionary / skiplist / binary tree of `PriceLevel` for sell orders (ascending price).
  - Fast BBO cache: $O(1)$ access to best bid and best ask.
  - `step(event) -> AuditRecord`: Atomic event execution producing complete before/after audit traces.
  - `check_invariants() -> BookInvariants`: Exhaustive invariant verification.

### `events.py`
- Normalized event dataclasses: `AddOrderEvent`, `ExecuteOrderEvent`, `CancelOrderEvent`, `DeleteOrderEvent`, `ReplaceOrderEvent`, `TradeEvent`, `BrokenTradeEvent`, `SystemEvent`, `TradingActionEvent`.
- `AuditRecord`: Captures event sequence number, event object, validation status, before/after states, TOB delta, and human-readable explanation.

### `statistics.py`
- Pure functional calculations:
  - Spread in price units and ticks.
  - Midpoint.
  - Top-of-book imbalance: $(Q_{bb} - Q_{ba}) / (Q_{bb} + Q_{ba})$.
  - Depth aggregates: Level 1, 5, 10, $N$.
  - Depth-weighted imbalance.
  - Volume at Price (VAP) distribution.
  - VWAP and cumulative trade counters.

### `feed_decoder.py`
- Decodes NASDAQ TotalView-ITCH 5.0 binary byte streams into normalized `Event` dataclasses.
- Validates field boundaries, message lengths, and character encodings.

### `moldudp64.py`
- Decodes 20-byte MoldUDP64 downstream headers.
- Extracts individual length-prefixed ITCH message blocks.
- Identifies heartbeats (`Message Count == 0`) and end of session (`Message Count == 0xFFFF`).

### `recovery.py`
- Receiver state machine:
  - `SEQUENCED`: Normal in-order reception.
  - `GAP_DETECTED`: Sequence jump detected; book marked invalid until missing packets received or replayed.
  - `RECOVERING`: Processing backfilled packets from request replay channel.
  - `INVALID`: Unrecoverable sequence error or corrupted feed.

### `reference_model.py`
- A minimal, brute-force order book that maintains orders in a simple list and computes BBO and depths via full linear scans. Used for differential property-based testing.
