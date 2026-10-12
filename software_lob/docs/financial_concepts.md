# Financial Concepts & Limit Order Book Fundamentals

This document provides the foundational financial concepts and market microstructure principles underlying the Limit Order Book (LOB) simulator. It serves as both an educational primer for engineers new to equity market mechanics and an exact behavioral specification for our software reference model and future FPGA hardware implementation.

---

## 1. Orders and Order Semantics

An **order** is an explicit instruction submitted by a market participant to buy or sell a specified quantity of a financial instrument under predetermined price constraints.

### Core Order Attributes

| Attribute | Type / Representation | Description |
| :--- | :--- | :--- |
| **Order ID** | `uint64` | A unique, non-repeating identifier assigned to the order by the exchange or trading venue. |
| **Side** | `BUY` (`Bid`) / `SELL` (`Ask`) | Identifies whether the participant intends to acquire or liquidate shares. |
| **Limit Price** | Integer units (`uint32`) | The worst allowable execution price. For a buy order, the maximum price willing to pay; for a sell order, the minimum price willing to accept. |
| **Original Quantity** | Integer shares (`uint32`) | The total number of shares initially submitted with the order. |
| **Remaining Quantity** | Integer shares (`uint32`) | The currently active, unexecuted share quantity resting in the order book. |
| **Executed Quantity** | Integer shares (`uint32`) | The cumulative number of shares that have traded against this order. |
| **Order Priority** | Timestamp / Sequence | The temporal queue position determining execution precedence among orders resting at the identical limit price. |

### Order Lifecycle States

An order progresses through well-defined lifecycle states:
1. **Open (Resting)**: The order has been accepted by the matching engine and rests in the book awaiting execution (`executed_qty == 0`, `remaining_qty == original_qty`).
2. **Partially Executed**: A fraction of the order's shares have traded, leaving the remainder displayed and active (`0 < executed_qty < original_qty`, `remaining_qty = original_qty - executed_qty`).
3. **Fully Executed (Filled)**: All shares have traded (`executed_qty == original_qty`, `remaining_qty == 0`). The order ceases to exist in the active book.
4. **Cancelled**: The participant cancelled the order prior to complete execution. If cancelled partially, `remaining_qty` is decreased; if cancelled in full or deleted, the order is removed entirely.

```
       [ Submit Order ]
              |
              v
       +--------------+     Partial Exec
       |     OPEN     | <-------------------+
       +--------------+                     |
         |          |                       |
Partial  |          | Full Exec             |
Cancel   v          v                       |
     [REDUCE]   +--------------+            |
         |      |    FILLED    |            |
         v      +--------------+            |
       +--------------+                     |
       |  CANCELLED   |                     |
       |  / DELETED   |                     |
       +--------------+                     |
              ^                             |
              +-----------------------------+
```

### Why a Buy Limit Order Differs from a Sell Limit Order

- **Buy Limit Order (Bid)**: Expresses a willingness to purchase *at or below* the limit price. A higher bid price is more aggressive because the buyer is willing to pay more.
- **Sell Limit Order (Ask / Offer)**: Expresses a willingness to sell *at or above* the limit price. A lower ask price is more aggressive because the seller is willing to accept less.

### Order Submission vs. Trade Execution

> [!IMPORTANT]
> **Key Distinction**: The appearance of an order in the market-data feed **does not mean a trade occurred**. 
> An `Add Order` message indicates passive liquidity being committed to the order book. A trade only occurs when an incoming aggressive order matches against a resting limit order, or during auction crossings.

#### Numeric Example: Order Lifecycle
A participant submits a Buy Limit Order:
- `Order ID`: 101
- `Side`: BUY
- `Limit Price`: ₹100.00 (represented as `1000000` in fixed-point 4-decimal integer units)
- `Quantity`: 50 shares

1. **State upon entry**: `remaining_qty = 50`, `executed_qty = 0`. Status is **OPEN**.
2. **First trade report (20 shares executed)**: `executed_qty = 20`, `remaining_qty = 50 - 20 = 30`. Status is **PARTIALLY EXECUTED**.
3. **Second trade report (remaining 30 shares executed)**: `executed_qty = 50`, `remaining_qty = 0`. Status is **FILLED**. The order is removed from the active order book.

---

## 2. The Limit Order Book Structure

The **Limit Order Book (LOB)** is a deterministic data structure maintained by an exchange (and replicated by market data consumers) containing all active, unexecuted limit orders sorted by price and time priority.

### Bids vs. Asks (Two-Sided Book)
- **Bid Side**: Stores all resting buy orders. Sorted in **descending order of price** (highest price first).
- **Ask Side**: Stores all resting sell orders. Sorted in **ascending order of price** (lowest price first).

### Price Levels and Aggregation
A **Price Level** represents a distinct limit price at which one or more resting orders exist.
- Multiple participants frequently submit orders at the same round price.
- The **Price-Level Aggregate Quantity** is the sum of `remaining_quantity` across all individual orders resting at that price level:
  $$\text{Aggregate Quantity}(P) = \sum_{i \in \text{Orders at } P} \text{remaining\_quantity}_i$$

### Price-Time Priority (FIFO)
When an aggressive order arrives at the exchange:
1. **Price Priority**: Orders at more favorable prices execute first. For buys, higher price has priority; for sells, lower price has priority.
2. **Time Priority (FIFO)**: Among orders resting at the exact same price level, orders that arrived earlier in time execute before orders that arrived later.

### Individual Orders vs. Price-Level Aggregates

| Dimension | Order-by-Order Book (L3 / ITCH) | Price-Aggregated Book (L2) |
| :--- | :--- | :--- |
| **Granularity** | Tracks each order ID and queue position | Tracks only $(Price, Total Quantity, Order Count)$ |
| **Memory in FPGA** | Requires order table / hash map + slot lists | Requires only price-indexed registers/BRAM |
| **Consumer Capability** | Can verify exact FIFO queue position and cancellations | Cannot attribute trades to specific resting orders |
| **Our System's Approach**| Internal L3 order tracking $\rightarrow$ aggregates into L2 levels and Top-of-Book |

#### Example: Two-Sided Aggregated Book

| Side | Price | Orders in Queue | Total Remaining Shares |
| :--- | :---:| :--- | :---:|
| **Bid** | ₹100.00 | Order A: 10 shares, Order B: 15 shares | **25** |
| **Bid** | ₹99.00 | Order C: 20 shares | **20** |
| **Ask** | ₹102.00 | Order D: 8 shares, Order E: 12 shares | **20** |
| **Ask** | ₹103.00 | Order F: 10 shares | **10** |

In this state:
- The **Best Bid** is ₹100.00 (highest buying price) with 25 total shares.
- The **Best Ask** is ₹102.00 (lowest selling price) with 20 total shares.
- Order A (10 shares) has FIFO precedence over Order B (15 shares) at the ₹100.00 price level.

---

## 3. Top of Book (TOB) and Best Bid and Offer (BBO)

The **Top of Book (TOB)**, also known as the **Best Bid and Offer (BBO)**, represents the prevailing most aggressive displayed buying and selling interest in the market.

### Formal Definitions

- **Best Bid Price ($P_{bb}$)**: $\max \{ P \mid P \in \text{Bids}, \text{Quantity}(P) > 0 \}$
- **Best Ask Price ($P_{ba}$)**: $\min \{ P \mid P \in \text{Asks}, \text{Quantity}(P) > 0 \}$
- **Best Bid Quantity ($Q_{bb}$)**: Total aggregate shares available at $P_{bb}$.
- **Best Ask Quantity ($Q_{ba}$)**: Total aggregate shares available at $P_{ba}$.
- **Tick Size ($\Delta_{tick}$)**: The minimum allowable price increment for the instrument (e.g., ₹0.05 or \$0.01). In integer fixed-point units (4 decimals), \$0.01 is `100`.

### Key TOB Metrics (Using Exact Integer Arithmetic)

1. **Bid–Ask Spread**:
   $$\text{Spread} = P_{ba} - P_{bb}$$
2. **Spread in Ticks**:
   $$\text{Spread}_{\text{ticks}} = \frac{P_{ba} - P_{bb}}{\Delta_{tick}}$$
3. **Midpoint**:
   $$\text{Midpoint} = \frac{P_{ba} + P_{bb}}{2}$$
   *(In integer price units, division by 2 truncates or rounds to nearest half-tick).*

### Special Market Conditions

- **Normal Market**: $P_{bb} < P_{ba}$ (Spread $> 0$).
- **Locked Market**: $P_{bb} == P_{ba}$ (Spread $== 0$). The best bid equals the best ask.
- **Crossed Market**: $P_{bb} > P_{ba}$ (Spread $< 0$). The best bid exceeds the best ask.
  > [!WARNING]
  > In an electronic matching engine, locked or crossed markets should not persist during regular trading because crossing orders execute immediately. However, a **market data consumer** may temporarily observe locked or crossed states due to:
  > - Packet reordering or transport delays.
  > - Auction imbalance dissemination phases prior to market open/close.
  > - Multi-venue consolidated feeds with latency differences.
- **Empty Side**: When there are zero resting bids or zero resting asks. In this case:
  - Best price is undefined (represented as `None` or sentinel `0` / `0xFFFFFFFF`).
  - Spread and midpoint are undefined.

> [!IMPORTANT]
> **Strict Integer Representation**:
> All prices and price calculations MUST use integer units internally. For example, ₹100.25 is stored as `1002500` ($100.25 \times 10^4$). Floating-point arithmetic is strictly prohibited in book state representation to prevent rounding errors and maintain exact bit-level congruence with hardware RTL.

---

## 4. Trade and Execution Mechanics

### What Occurs During an Execution?
An execution occurs when liquidity is removed from the book. In an order-driven feed:
1. An incoming market or aggressive limit order matches against a resting limit order.
2. The exchange publishes an **Order Executed** message referencing the resting order's `Order ID`.
3. The message specifies `Executed Quantity` and optionally an `Execution Price` and `Match Number`.

### Partial vs. Full Execution
- **Partial Execution**: The executed quantity is strictly less than the order's remaining quantity.
  $$\text{New Remaining Qty} = \text{Old Remaining Qty} - \text{Executed Qty}$$
- **Full Execution**: The executed quantity equals the order's remaining quantity. The order is completely filled and deleted from the book.

### Crucial Consumer Responsibilities
1. **Execution Reports vs. Order Removals**: An execution report records that a trade occurred and reduces resting quantity. An order deletion/cancel report removes quantity without a trade.
2. **Do Not Invent Counterparties**: In ITCH feeds, execution messages identify the resting order that was filled. The consumer **must not fabricate or invent the aggressive counterparty order**. The aggressive order matched immediately upon arrival and was never resting in the book.
3. **Execution Reports are Declarative**: Execution messages are notifications of past events that occurred at the exchange matching engine, not instructions or requests to initiate new trades.

---

## 5. Order Lifecycle Events and State Transitions

| Event | Input Arguments | Impact on Order State | Impact on Price Level | Impact on Best Bid/Ask |
| :--- | :--- | :--- | :--- | :--- |
| **Add Order** | `order_id, side, price, qty` | New order record created with `remaining_qty = qty`. Enqueued at end of FIFO list. | Level created if new; aggregate qty increased by `qty`; order count incremented. | Updates BBO if `side == BUY` and `price > best_bid`, or `side == SELL` and `price < best_ask`. |
| **Cancel Order (Partial)** | `order_id, canceled_qty` | Decreases `remaining_qty` by `canceled_qty`. FIFO position preserved. | Level aggregate qty decreased by `canceled_qty`. Order count unchanged. | Updates BBO quantity if order is at the best level. |
| **Delete Order (Full)** | `order_id` | Order removed completely from book memory. | Level aggregate qty decreased by remaining qty; order count decremented. Level removed if count becomes 0. | If order was at best level and was last order, best price advances to next best level. |
| **Order Executed** | `order_id, executed_qty, match_num` | Decreases `remaining_qty` by `executed_qty`. If remaining becomes 0, order removed. | Level aggregate qty decreased. Level removed if empty. | Updates BBO quantity (and price if level depleted). Trade stats updated. |
| **Order Executed with Price** | `order_id, executed_qty, match_num, exec_price` | Identical to Order Executed, but trade took place at `exec_price` rather than order's limit price. | Level aggregate qty decreased. Level removed if empty. | Updates BBO. Trade stats record explicit `exec_price`. |
| **Replace Order** | `old_id, new_id, new_price, new_qty` | Old order is completely removed. New order is created with `new_id`, `new_price`, and `new_qty`. | Old price level reduced/removed. New price level created/increased. | May alter BBO on both old and new price levels. |

### Note on Order Replace Semantics
> [!WARNING]
> Under NASDAQ ITCH semantics, an **Order Replace** is equivalent to an atomic cancel-and-replace: the original order `old_order_id` is eliminated, and a brand-new order `new_order_id` is introduced at the end of the queue for `new_price`. **It does not preserve time priority**.

---

## 6. Financial Statistics & Microstructure Metrics

All market statistics are derived deterministically from the current state of the book and the history of execution reports.

### 1. Top-of-Book Imbalance
Measures the directional skew between buying and selling pressure at the BBO:
$$\text{Imbalance} = \frac{Q_{bb} - Q_{ba}}{Q_{bb} + Q_{ba}}$$
- Range: $[-1.0, +1.0]$.
  - $+1.0$: Pure buying pressure (no asks).
  - $-1.0$: Pure selling pressure (no bids).
  - $0.0$: Perfectly balanced.
- **Edge Case**: If $Q_{bb} + Q_{ba} == 0$, $\text{Imbalance} = 0.0$.

### 2. Multi-Level Depth (Levels 1, 5, 10, $N$)
Total displayed liquidity up to $N$ price levels away from the market:
$$\text{Depth}_{\text{bid}}(N) = \sum_{k=1}^{\min(N, |Bids|)} Q_{\text{bid}, k}, \quad \text{Depth}_{\text{ask}}(N) = \sum_{k=1}^{\min(N, |Asks|)} Q_{\text{ask}, k}$$

### 3. Depth-Weighted Imbalance
Weighting price levels closer to the BBO higher than deeper levels:
$$\text{DWI}(N) = \frac{\sum_{k=1}^N \frac{1}{k} Q_{\text{bid}, k} - \sum_{k=1}^N \frac{1}{k} Q_{\text{ask}, k}}{\sum_{k=1}^N \frac{1}{k} Q_{\text{bid}, k} + \sum_{k=1}^N \frac{1}{k} Q_{\text{ask}, k}}$$

### 4. Volume at Price (VAP)
Total accumulated executed shares at each distinct trade price level.

### 5. Cumulative Traded Volume & Trade Count
- $\text{Total Volume} = \sum \text{executed\_qty}$ across all execution reports and non-cross trade messages.
- $\text{Trade Count} = \text{Total number of execution / trade reports received}$.

### 6. Volume-Weighted Average Price (VWAP)
The benchmark average price weighted by execution volume:
$$\text{VWAP} = \frac{\sum_{i=1}^M (\text{Price}_i \times \text{Quantity}_i)}{\sum_{i=1}^M \text{Quantity}_i}$$
*(Calculated only over trades where execution price and quantity are known. For ITCH 'E' messages, the trade price is the resting order's limit price; for 'C' and 'P' messages, the explicit execution price is used).*

---

## 7. Passive Order Book vs. Full Market Reality

> [!NOTE]
> The displayed limit order book reconstructed from ITCH represents **visible, displayed liquidity**. It does not capture:
> 1. **Hidden Orders**: Reserve or iceberg orders whose full size is concealed.
> 2. **Dark Pools**: Off-exchange crossing networks.
> 3. **Order Routing**: Orders routed to other competing exchanges.
> 
> Therefore, all derived metrics represent the visible state of the single exchange feed and should never be construed as investment advice or complete predictors of future price movements.
