# Comprehensive Test Plan & Verification Strategy

This document establishes the test strategy, verification matrix, invariant checks, and property-based testing methodology for the Python Limit Order Book simulator.

---

## 1. Testing Objectives

1. **Deterministic Functional Verification**: Guarantee that the Python reference model behaves deterministically and conforms to NASDAQ TotalView-ITCH 5.0 and market microstructure principles.
2. **Defensive Robustness**: Ensure that invalid inputs, malformed packets, and sequence gaps are safely rejected without corrupting book state.
3. **Differential Equivalence**: Verify the primary `OrderBook` against a naive brute-force `ReferenceModel` using Hypothesis property-based fuzzing.
4. **Hardware Validation Testbenches**: Provide golden reference test vectors for RTL simulation.

---

## 2. Test Classification Matrix

| Category | Target Module | Scope & Methodology |
| :--- | :--- | :--- |
| **Unit Tests** | `order_book.py`, `price_levels.py`, `statistics.py` | Isolated testing of every event type, price level operations, and metric calculations. |
| **Scenario Tests** | `scenarios.py` | Implementation and verification of worked Scenarios A through H from the specification. |
| **Invariant Tests** | `order_book.py` | Verification of structural and mathematical invariants after every valid state mutation. |
| **Property-Based Tests** | `order_book.py` vs `reference_model.py` | Hypothesis fuzz testing with random valid/invalid event sequences, checking differential outputs. |
| **Feed Decoding Tests** | `feed_decoder.py` | Binary decoding of all 13 ITCH 5.0 message types against byte fixtures, boundary checks. |
| **Transport & Recovery** | `moldudp64.py`, `recovery.py` | Packet framing, heartbeat handling, sequence gaps, duplicate packets, state machine transitions. |
| **Regression Tests** | Whole system | Targeted tests preventing regression of identified edge cases and boundary conditions. |

---

## 3. Structural & Mathematical Invariants

After every processed event, the book must satisfy all of the following invariants:

1. **Positive Remaining Quantity**:
   $$\forall o \in \text{orders}, \quad o.\text{remaining\_qty} > 0$$
2. **Unique Order IDs**:
   No duplicate order IDs exist across either side of the book.
3. **Consistent Side & Price Level**:
   Every active order belongs to exactly one side (`BUY` or `SELL`) and exists within exactly one `PriceLevel` whose price matches `order.price`.
4. **Aggregate Level Conservation**:
   For every `PriceLevel` $L$ at price $P$:
   $$L.\text{total\_quantity} == \sum_{o \in L.\text{orders}} o.\text{remaining\_qty}$$
   $$L.\text{order\_count} == |L.\text{orders}|$$
5. **No Empty Price Levels**:
   No `PriceLevel` exists in the book with $L.\text{order\_count} == 0$ or $L.\text{total\_quantity} == 0$.
6. **Correct Top-of-Book**:
   - If bids are non-empty: $\text{best\_bid} == \max_{L \in \text{bids}} L.\text{price}$.
   - If asks are non-empty: $\text{best\_ask} == \min_{L \in \text{asks}} L.\text{price}$.
7. **Conservation of Shares on Mutation**:
   $$\text{Executed Shares} + \text{Canceled Shares} + \text{Remaining Shares} == \text{Original Shares}$$
   Execution or cancellation can never create shares or exceed remaining quantity.
8. **Independent Cross-Check Equivalence**:
   Every calculated metric (spread, midpoint, imbalance, VWAP) must exactly match an independent calculation performed directly from active order lists.

---

## 4. Detailed Test Cases

### 4.1. Worked Scenarios (A – H)
- **Scenario A (Add Orders & TOB)**: Bids at ₹100 (50), ₹99 (30); Asks at ₹103 (20), ₹102 (15). Verify BBO: Bid ₹100 × 50, Ask ₹102 × 15, Spread ₹2, Midpoint ₹101.
- **Scenario B (Partial & Full Execution)**: Buy 50 @ ₹100. Execute 20 -> remaining 30. Execute 30 -> order removed, price level pruned.
- **Scenario C (Cancellation & Deletion)**: Buy 50 @ ₹100. Cancel 15 -> remaining 35. Delete -> removed. Rejection of cancellations exceeding remaining quantity.
- **Scenario D (Dynamic TOB Transitions)**: Step-by-step price improvement, best level depletion, side exhaustion, and replenishment.
- **Scenario E (Price-Time FIFO Priority)**: Three orders at identical price: A (10), B (20), C (30). Partial execution of A. Removal of A. Verify B remains head of queue, followed by C.
- **Scenario F (Order Replace)**: Replace order with modified price and quantity. Verify old order removed, new order ID created, time priority reset to queue tail.
- **Scenario G (Trade Reporting & VWAP)**: Execution at limit price, execution at improved price ('C'), non-displayed trade ('P'), broken trade ('B'). Verify VWAP arithmetic without double counting.
- **Scenario H (Invalid Inputs & Defensive Rejection)**: Duplicate order ID, unknown order ID, negative quantity, zero price, over-cancellation, over-execution. Ensure book state is unmodified.

### 4.2. Transport & Recovery Tests
- Sequential MoldUDP64 packets with single and multi-message payloads.
- Heartbeat packets (`Message Count == 0`) advancing expected sequence number.
- Packet sequence gap (e.g. expected 10, received 12): transition to `GAP_DETECTED`, book marked invalid.
- Recovery buffer: replay packets filling gap, transition back to `SEQUENCED`, book valid.
- Corrupted/truncated packet rejection.
