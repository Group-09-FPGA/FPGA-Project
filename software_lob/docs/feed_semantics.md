# NASDAQ TotalView-ITCH 5.0 & MoldUDP64 Protocol Semantics

This document establishes the verified binary protocol definitions, byte offsets, field layouts, and state transition semantics for **NASDAQ TotalView-ITCH 5.0** and the **MoldUDP64** transport layer.

**Authoritative Sources**:
- *NASDAQ TotalView-ITCH 5.0 Interface Specification* (Nasdaq Global Data Products, Document Version 5.0).
- *MoldUDP64 Protocol Specification* (Nasdaq Trader Technical Support).

---

## 1. Transport Protocol: MoldUDP64

MoldUDP64 is a lightweight, connectionless point-to-multipoint transport protocol built on top of UDP. It guarantees in-order sequencing and detects packet loss across downstream market data feeds.

### A. Downstream Packet Header Format
Every MoldUDP64 downstream packet starts with a 20-byte fixed header in **Network Byte Order (Big-Endian)**.

| Field Name | Offset | Length | Type | Description |
| :--- | :---: | :---: | :--- | :--- |
| **Session** | 0 | 10 | ASCII (`char[10]`) | Alphanumeric identifier of the current data session. Left-justified, space-padded. |
| **Sequence Number** | 10 | 8 | Integer (`uint64_be`) | Sequence number of the first payload message contained in this packet. Starts at 1 daily. |
| **Message Count** | 18 | 2 | Integer (`uint16_be`) | Number of ITCH message blocks contained in this packet. |

### B. Special Message Count Values
- `Message Count == 0`: **Heartbeat Packet**. Contains no message blocks (packet length = 20 bytes). The `Sequence Number` field conveys the *next expected sequence number* the session will broadcast.
- `Message Count == 0xFFFF` (65535): **End of Session Packet**. Indicates no further messages will be transmitted for this session.

### C. Message Block Framing
When `Message Count > 0`, the header is followed immediately by variable-length message blocks:
```
+-------------------------------------------------------+
|             MoldUDP64 Header (20 bytes)               |
+-------------------------------------------------------+
| Length 1 (2B) | Message 1 Payload (Length 1 bytes)    |
+-------------------------------------------------------+
| Length 2 (2B) | Message 2 Payload (Length 2 bytes)    |
+-------------------------------------------------------+
| ...                                                   |
+-------------------------------------------------------+
| Length N (2B) | Message N Payload (Length N bytes)    |
+-------------------------------------------------------+
```
- **Message Length**: 2 bytes (`uint16_be`), gives the exact length of the message payload that follows.
- Payload contains exactly one ITCH 5.0 binary message.

---

## 2. Common ITCH 5.0 Header Format

All ITCH 5.0 messages begin with a common 11-byte header:

| Field Name | Offset | Length | Type | Description |
| :--- | :---: | :---: | :--- | :--- |
| **Message Type** | 0 | 1 | ASCII (`char`) | Single-character identifier of the message type (e.g., `'A'`, `'E'`). |
| **Stock Locate** | 1 | 2 | Integer (`uint16_be`) | Unique integer assigned daily identifying the security symbol. |
| **Tracking Number** | 3 | 2 | Integer (`uint16_be`) | Internal tracking number assigned by NASDAQ trading system. |
| **Timestamp** | 5 | 6 | Integer (`uint48_be`) | Nanoseconds since midnight ($0$ to $86,400,000,000,000$). |

> [!NOTE]
> **48-Bit Timestamp Decoding**: In Python, 6-byte big-endian integers are decoded using:
> `timestamp_ns = int.from_bytes(data[5:11], byteorder='big')`

---

## 3. Supported ITCH 5.0 Message Specifications

### 3.1. Add Order Message — No MPID (Type `'A'`)

- **Official Name**: Add Order Message
- **Message Type**: `'A'` (0x41)
- **Total Length**: 36 bytes

#### Binary Layout:
| Field Name | Offset | Length | Type | Description |
| :--- | :---: | :---: | :--- | :--- |
| Header (Common) | 0 | 11 | Struct | Message Type (`'A'`), Stock Locate, Tracking Number, Timestamp |
| **Order Reference Number** | 11 | 8 | `uint64_be` | Unique order identifier assigned to this limit order. |
| **Buy/Sell Indicator** | 19 | 1 | `char` | `'B'` = Buy (Bid), `'S'` = Sell (Ask). |
| **Shares** | 20 | 4 | `uint32_be` | Number of shares added. |
| **Stock** | 24 | 8 | `char[8]` | Security symbol, right-padded with spaces (ASCII). |
| **Price** | 32 | 4 | `uint32_be` | Fixed-point integer price with 4 implied decimal places. |

#### State & Behavioral Semantics:
1. **Order-Book State Changes**: A new order is inserted into the book with `order_id = Order Reference Number`, `remaining_qty = Shares`, `price = Price`, `side = Side`. The order is enqueued at the tail of the corresponding `PriceLevel` (preserving FIFO priority).
2. **Trade Statistics**: No trade statistics change. Order addition count increments.
3. **Order ID Requirement**: Order ID **must not exist** in the book. If duplicate, event is rejected with an audit error.
4. **Applicable to Displayed Book**: Yes.
5. **Invalid Handling**: Rejected if duplicate order ID, zero shares, zero price, or unrecognized side.

#### Minimal Binary Fixture:
```python
# 'A', Locate=1, Track=1, Time=36000000000000 (10:00:00), OrderID=101, Side='B', Shares=50, Stock="AAPL    ", Price=1000000 ($100.0000)
fixture_a = bytes.fromhex(
    "41"                  # Type 'A'
    "0001"                # Locate 1
    "0001"                # Tracking 1
    "000020c49ba5e000"    # Timestamp 36000000000000 ns (6 bytes: 20c49ba5e000)
    "0000000000000065"    # Order Reference Number 101
    "42"                  # Side 'B'
    "00000032"            # Shares 50
    "4141504c20202020"    # Stock "AAPL    "
    "000f4240"            # Price 1000000 ($100.0000)
)
assert len(fixture_a) == 36
```
#### Expected State:
- Book contains Order 101 resting at Bid ₹100.00 for 50 shares.
- Best Bid = ₹100.00 × 50 shares.

---

### 3.2. Add Order with MPID Attribution (Type `'F'`)

- **Official Name**: Add Order with MPID Attribution Message
- **Message Type**: `'F'` (0x46)
- **Total Length**: 40 bytes

#### Binary Layout:
Same as Type `'A'` (bytes 0–35), plus:
| Field Name | Offset | Length | Type | Description |
| :--- | :---: | :---: | :--- | :--- |
| **Attribution** | 36 | 4 | `char[4]` | Market Participant Identifier (MPID) (e.g., `"GSCO"`). |

#### Semantics:
Identical to Type `'A'`, with MPID metadata stored in order record for attribution display.

---

### 3.3. Order Executed Message (Type `'E'`)

- **Official Name**: Order Executed Message
- **Message Type**: `'E'` (0x45)
- **Total Length**: 31 bytes

#### Binary Layout:
| Field Name | Offset | Length | Type | Description |
| :--- | :---: | :---: | :--- | :--- |
| Header (Common) | 0 | 11 | Struct | Message Type (`'E'`), Locate, Tracking, Timestamp |
| **Order Reference Number** | 11 | 8 | `uint64_be` | Resting order identifier being executed. |
| **Executed Shares** | 19 | 4 | `uint32_be` | Number of shares executed in this transaction. |
| **Match Number** | 23 | 8 | `uint64_be` | Exchange match identifier assigned to this trade. |

#### State & Behavioral Semantics:
1. **Order-Book State Changes**: Locates order by `Order Reference Number`. Decreases `remaining_qty` by `Executed Shares`. If `remaining_qty == 0`, order is deleted from the book and price level. If price level becomes empty, price level is removed.
2. **Trade Statistics**: 
   - Cumulative executed volume increases by `Executed Shares`.
   - Trade count increments by 1.
   - Traded price is the resting order's limit price. VWAP updated: $\text{VWAP}_{\text{new}} = \frac{\text{sum\_notional} + (\text{limit\_price} \times \text{shares})}{\text{sum\_shares} + \text{shares}}$.
   - Volume at Price (VAP) increments by `Executed Shares` at resting order's price.
3. **Order ID Requirement**: Order ID **must exist**. If unknown, rejected with audit error.
4. **Applicable to Displayed Book**: Yes.
5. **Invalid Handling**: Rejected if `Executed Shares > remaining_qty` or `Executed Shares == 0`.

#### Minimal Binary Fixture:
```python
# 'E', Locate=1, Track=1, Time=36000000001000, OrderID=101, ExecShares=20, MatchNum=5001
fixture_e = bytes.fromhex(
    "45"                  # Type 'E'
    "0001"                # Locate 1
    "0001"                # Tracking 1
    "000020c49ba5e3e8"    # Timestamp
    "0000000000000065"    # Order Reference Number 101
    "00000014"            # Executed Shares 20
    "0000000000001389"    # Match Number 5001
)
assert len(fixture_e) == 31
```
#### Expected State:
- Order 101 remaining quantity reduced from 50 to 30.
- Level aggregate quantity reduced by 20. Total traded volume = 20.

---

### 3.4. Order Executed with Price Message (Type `'C'`)

- **Official Name**: Order Executed with Price Message
- **Message Type**: `'C'` (0x43)
- **Total Length**: 36 bytes

#### Binary Layout:
| Field Name | Offset | Length | Type | Description |
| :--- | :---: | :---: | :--- | :--- |
| Header (Common) | 0 | 11 | Struct | Message Type (`'C'`), Locate, Tracking, Timestamp |
| **Order Reference Number** | 11 | 8 | `uint64_be` | Resting order identifier being executed. |
| **Executed Shares** | 19 | 4 | `uint32_be` | Number of shares executed. |
| **Match Number** | 23 | 8 | `uint64_be` | Exchange match identifier. |
| **Printable** | 31 | 1 | `char` | `'Y'` = Eligible for trade reporting; `'N'` = Non-printable. |
| **Execution Price** | 32 | 4 | `uint32_be` | The actual trade execution price (4 decimal places). |

#### State & Behavioral Semantics:
Identical to Type `'E'`, except:
- VWAP and Volume at Price (VAP) are computed using the explicit **Execution Price** instead of the order's resting limit price.

---

### 3.5. Order Cancel Message — Partial (Type `'X'`)

- **Official Name**: Order Cancel Message
- **Message Type**: `'X'` (0x58)
- **Total Length**: 23 bytes

#### Binary Layout:
| Field Name | Offset | Length | Type | Description |
| :--- | :---: | :---: | :--- | :--- |
| Header (Common) | 0 | 11 | Struct | Message Type (`'X'`), Locate, Tracking, Timestamp |
| **Order Reference Number** | 11 | 8 | `uint64_be` | Order identifier to cancel partially. |
| **Canceled Shares** | 19 | 4 | `uint32_be` | Number of shares to cancel/remove. |

#### State & Behavioral Semantics:
1. **Order-Book State Changes**: Decreases `remaining_qty` by `Canceled Shares`. The order remains at its current price level and **retains its FIFO time priority**. If `Canceled Shares == remaining_qty`, the order is deleted from book.
2. **Trade Statistics**: No trade statistics change. Cancellation counters increment.
3. **Order ID Requirement**: Order ID **must exist**.
4. **Applicable to Displayed Book**: Yes.
5. **Invalid Handling**: Rejected if `Canceled Shares > remaining_qty` or `Canceled Shares == 0`.

---

### 3.6. Order Delete Message — Full (Type `'D'`)

- **Official Name**: Order Delete Message
- **Message Type**: `'D'` (0x44)
- **Total Length**: 19 bytes

#### Binary Layout:
| Field Name | Offset | Length | Type | Description |
| :--- | :---: | :---: | :--- | :--- |
| Header (Common) | 0 | 11 | Struct | Message Type (`'D'`), Locate, Tracking, Timestamp |
| **Order Reference Number** | 11 | 8 | `uint64_be` | Order identifier to delete in full. |

#### State & Behavioral Semantics:
1. **Order-Book State Changes**: The order is looked up and deleted entirely from the book. Price level quantity is reduced by the order's remaining shares, and order count decremented. If price level has 0 orders, level is pruned.
2. **Trade Statistics**: No trade statistics change. Deletion counters increment.
3. **Order ID Requirement**: Order ID **must exist**.
4. **Applicable to Displayed Book**: Yes.
5. **Invalid Handling**: Rejected if order ID unknown.

---

### 3.7. Order Replace Message (Type `'U'`)

- **Official Name**: Order Replace Message
- **Message Type**: `'U'` (0x55)
- **Total Length**: 35 bytes

#### Binary Layout:
| Field Name | Offset | Length | Type | Description |
| :--- | :---: | :---: | :--- | :--- |
| Header (Common) | 0 | 11 | Struct | Message Type (`'U'`), Locate, Tracking, Timestamp |
| **Original Order Reference Number** | 11 | 8 | `uint64_be` | Existing order to cancel. |
| **New Order Reference Number** | 19 | 8 | `uint64_be` | New replacement order ID. |
| **Shares** | 27 | 4 | `uint32_be` | New total quantity of replacement order. |
| **Price** | 31 | 4 | `uint32_be` | New limit price of replacement order. |

#### State & Behavioral Semantics:
1. **Order-Book State Changes**:
   - `Original Order Reference Number` is deleted completely.
   - A new order record with `New Order Reference Number`, `Shares`, and `Price` is inserted into the book with the original order's `side`.
   - The new order is appended to the **tail** of the queue at `Price` (new time priority).
2. **Trade Statistics**: No trade statistics change.
3. **Order ID Requirement**: `Original Order Reference Number` **must exist**; `New Order Reference Number` **must not exist**.
4. **Applicable to Displayed Book**: Yes.
5. **Invalid Handling**: Rejected if original ID unknown or new ID already exists.

---

### 3.8. Trade Message — Non-Cross (Type `'P'`)

- **Official Name**: Trade Message (Non-Cross)
- **Message Type**: `'P'` (0x50)
- **Total Length**: 44 bytes

#### Binary Layout:
| Field Name | Offset | Length | Type | Description |
| :--- | :---: | :---: | :--- | :--- |
| Header (Common) | 0 | 11 | Struct | Message Type (`'P'`), Locate, Tracking, Timestamp |
| **Order Reference Number** | 11 | 8 | `uint64_be` | For non-displayed executions, NASDAQ sets this to `0`. |
| **Buy/Sell Indicator** | 19 | 1 | `char` | `'B'` or `'S'`. |
| **Shares** | 20 | 4 | `uint32_be` | Number of shares traded. |
| **Stock** | 24 | 8 | `char[8]` | Stock symbol. |
| **Price** | 32 | 4 | `uint32_be` | Execution price (4 decimal places). |
| **Match Number** | 36 | 8 | `uint64_be` | Session-unique execution match number. |

#### State & Behavioral Semantics:
1. **Order-Book State Changes**: **None**. This message reports an execution involving a non-displayed order type (hidden/iceberg). It does NOT alter displayed order book levels.
2. **Trade Statistics**: 
   - Cumulative traded volume increments by `Shares`.
   - Trade count increments.
   - Contributes to VWAP and Volume at Price at `Price`.
3. **Order ID Requirement**: Not required to exist in the displayed book (typically 0).

---

### 3.9. Cross Trade Message (Type `'Q'`)

- **Official Name**: Cross Trade Message
- **Message Type**: `'Q'` (0x51)
- **Total Length**: 40 bytes

#### Binary Layout:
| Field Name | Offset | Length | Type | Description |
| :--- | :---: | :---: | :--- | :--- |
| Header (Common) | 0 | 11 | Struct | Message Type (`'Q'`), Locate, Tracking, Timestamp |
| **Shares** | 11 | 8 | `uint64_be` | Number of shares paired and executed in the cross. |
| **Stock** | 19 | 8 | `char[8]` | Stock symbol. |
| **Cross Price** | 27 | 4 | `uint32_be` | Crossing price (4 decimal places). |
| **Match Number** | 31 | 8 | `uint64_be` | Match number. |
| **Cross Type** | 39 | 1 | `char` | `'O'` = Opening, `'C'` = Closing, `'H'` = Halt/IPO cross. |

#### State & Behavioral Semantics:
Reports completion of opening or closing auction cross. Updates cumulative volume and cross trade statistics; does not modify displayed intraday book directly.

---

### 3.10. Broken Trade Message (Type `'B'`)

- **Official Name**: Broken Trade / Break Order Message
- **Message Type**: `'B'` (0x42)
- **Total Length**: 19 bytes

#### Binary Layout:
| Field Name | Offset | Length | Type | Description |
| :--- | :---: | :---: | :--- | :--- |
| Header (Common) | 0 | 11 | Struct | Message Type (`'B'`), Locate, Tracking, Timestamp |
| **Match Number** | 11 | 8 | `uint64_be` | Match number of the previously broadcast trade being broken. |

#### State & Behavioral Semantics:
1. **Order-Book State Changes**: **None**. Broken trades cannot resurrect resting orders that were already removed from the book.
2. **Trade Statistics**: Subtracts the broken trade's quantity and notional value from cumulative volume, trade count, and VWAP if tracked in the session's trade execution journal.

---

### 3.11. System Event Message (Type `'S'`)

- **Official Name**: System Event Message
- **Message Type**: `'S'` (0x53)
- **Total Length**: 12 bytes

#### Binary Layout:
| Field Name | Offset | Length | Type | Description |
| :--- | :---: | :---: | :--- | :--- |
| Header (Common) | 0 | 11 | Struct | Message Type (`'S'`), Locate, Tracking, Timestamp |
| **Event Code** | 11 | 1 | `char` | `'O'` = Start of Messages, `'S'` = Start of System Hours, `'Q'` = Start of Market Hours, `'M'` = End of Market Hours, `'E'` = End of System Hours, `'C'` = End of Messages. |

---

### 3.12. Stock Directory Message (Type `'R'`)

- **Official Name**: Stock Directory Message
- **Message Type**: `'R'` (0x52)
- **Total Length**: 39 bytes
- Maps `Stock Locate` (2 bytes) to security symbol `Stock` (8 bytes) and establishes trading rules (Round Lot Size, Financial Status).

---

### 3.13. Stock Trading Action Message (Type `'H'`)

- **Official Name**: Stock Trading Action Message
- **Message Type**: `'H'` (0x48)
- **Total Length**: 25 bytes
- Indicates whether trading in a stock is `'T'` (Trading), `'H'` (Halted), or `'P'` (Paused).

---

## 4. Normalized Internal Event Mapping

To maintain strict separation of concerns, the binary feed decoder produces normalized internal events consumed by the core engine:

| ITCH Message | Normalized Internal Event |
| :--- | :--- |
| `'A'` (Add Order) | `AddOrderEvent(order_id, side, price, quantity, timestamp, mpid=None)` |
| `'F'` (Add Order MPID) | `AddOrderEvent(order_id, side, price, quantity, timestamp, mpid=attr)` |
| `'E'` (Order Executed) | `ExecuteOrderEvent(order_id, executed_qty, match_num, price=None, timestamp)` |
| `'C'` (Order Executed w/ Price) | `ExecuteOrderEvent(order_id, executed_qty, match_num, price=exec_price, timestamp)` |
| `'X'` (Order Cancel) | `CancelOrderEvent(order_id, canceled_qty, timestamp)` |
| `'D'` (Order Delete) | `DeleteOrderEvent(order_id, timestamp)` |
| `'U'` (Order Replace) | `ReplaceOrderEvent(old_order_id, new_order_id, new_price, new_qty, timestamp)` |
| `'P'` (Trade Non-Cross) | `TradeEvent(match_number, side, shares, stock, price, timestamp)` |
| `'B'` (Broken Trade) | `BrokenTradeEvent(match_number, timestamp)` |
| `'S'` (System Event) | `SystemEvent(event_code, timestamp)` |
| `'H'` (Trading Action) | `TradingActionEvent(stock, state, reason, timestamp)` |
