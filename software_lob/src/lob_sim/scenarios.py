"""Pre-built deterministic scenarios A through H from specification."""

from __future__ import annotations

from typing import Callable

from lob_sim.events import (
    AddOrderEvent,
    AuditRecord,
    BaseEvent,
    BrokenTradeEvent,
    CancelOrderEvent,
    DeleteOrderEvent,
    ExecuteOrderEvent,
    ReplaceOrderEvent,
    TradeEvent,
)
from lob_sim.models import Side
from lob_sim.order_book import OrderBook


def build_scenario_a() -> list[BaseEvent]:
    """Scenario A: Add orders and verify TOB shifts."""
    return [
        AddOrderEvent(
            order_id=101, side=Side.BUY, price=1000000, quantity=50
        ),  # ₹100.00
        AddOrderEvent(
            order_id=102, side=Side.BUY, price=990000, quantity=30
        ),  # ₹99.00
        AddOrderEvent(
            order_id=201, side=Side.SELL, price=1030000, quantity=20
        ),  # ₹103.00
        AddOrderEvent(
            order_id=202, side=Side.SELL, price=1020000, quantity=15
        ),  # ₹102.00
    ]


def build_scenario_b() -> list[BaseEvent]:
    """Scenario B: Partial and full execution."""
    return [
        AddOrderEvent(
            order_id=101, side=Side.BUY, price=1000000, quantity=50
        ),  # Buy 50 @ ₹100
        ExecuteOrderEvent(
            order_id=101, executed_qty=20, match_number=5001
        ),  # Exec 20
        ExecuteOrderEvent(
            order_id=101, executed_qty=30, match_number=5002
        ),  # Exec remaining 30
    ]


def build_scenario_c() -> list[BaseEvent]:
    """Scenario C: Cancellation and deletion."""
    return [
        AddOrderEvent(
            order_id=301, side=Side.BUY, price=1000000, quantity=50
        ),  # Buy 50 @ ₹100
        CancelOrderEvent(order_id=301, canceled_qty=15),  # Cancel 15 -> rem 35
        DeleteOrderEvent(order_id=301),  # Delete full -> level pruned
    ]


def build_scenario_d() -> list[BaseEvent]:
    """Scenario D: Dynamic Top-of-Book shifts, level depletion, and restoration."""
    return [
        # Setup initial book
        AddOrderEvent(order_id=401, side=Side.BUY, price=1000000, quantity=10),
        AddOrderEvent(order_id=402, side=Side.BUY, price=990000, quantity=20),
        AddOrderEvent(order_id=403, side=Side.SELL, price=1020000, quantity=15),
        AddOrderEvent(order_id=404, side=Side.SELL, price=1030000, quantity=25),
        # 1. Price improvement on Bid: Add @ ₹101
        AddOrderEvent(order_id=405, side=Side.BUY, price=1010000, quantity=5),
        # 2. Execute last order at best bid (depletes ₹101 level)
        ExecuteOrderEvent(order_id=405, executed_qty=5, match_number=6001),
        # 3. Cancel the only order at best ask (₹102 level)
        CancelOrderEvent(order_id=403, canceled_qty=15),
        # 4. Remove all bids to create empty bid side
        DeleteOrderEvent(order_id=401),
        DeleteOrderEvent(order_id=402),
        # 5. Restore previously empty bid side
        AddOrderEvent(order_id=406, side=Side.BUY, price=1005000, quantity=40),
    ]


def build_scenario_e() -> list[BaseEvent]:
    """Scenario E: Price-time priority (FIFO queue order preservation)."""
    return [
        # Add orders A, B, C at identical price ₹100.00
        AddOrderEvent(
            order_id=501, side=Side.BUY, price=1000000, quantity=10
        ),  # A
        AddOrderEvent(
            order_id=502, side=Side.BUY, price=1000000, quantity=20
        ),  # B
        AddOrderEvent(
            order_id=503, side=Side.BUY, price=1000000, quantity=30
        ),  # C
        # Partially execute A (5 shares) -> A retains queue position
        ExecuteOrderEvent(order_id=501, executed_qty=5, match_number=7001),
        # Fully execute remaining of A (5 shares) -> A removed, B becomes head
        ExecuteOrderEvent(order_id=501, executed_qty=5, match_number=7002),
    ]


def build_scenario_f() -> list[BaseEvent]:
    """Scenario F: Order replace (identity change, price/qty shift, priority reset)."""
    return [
        AddOrderEvent(
            order_id=601, side=Side.BUY, price=1000000, quantity=50
        ),  # Priority 1
        AddOrderEvent(
            order_id=602, side=Side.BUY, price=1000000, quantity=25
        ),  # Priority 2
        # Replace 601 with 603 at same price ₹100, qty 40 -> moves to TAIL (behind 602)
        ReplaceOrderEvent(
            old_order_id=601,
            new_order_id=603,
            new_price=1000000,
            new_quantity=40,
        ),
        # Replace 603 with 604 at improved price ₹101 -> becomes new BBO
        ReplaceOrderEvent(
            old_order_id=603,
            new_order_id=604,
            new_price=1010000,
            new_quantity=30,
        ),
    ]


def build_scenario_g() -> list[BaseEvent]:
    """Scenario G: Trade reporting, non-displayed trades, VWAP, and broken trades."""
    return [
        AddOrderEvent(
            order_id=701, side=Side.SELL, price=1000000, quantity=100
        ),  # 100 @ 100
        # 1. Execution at limit price: 40 @ 100
        ExecuteOrderEvent(
            order_id=701, executed_qty=40, match_number=8001
        ),  # Notional: 40 * 100
        # 2. Execution at improved price 'C': 30 @ 101
        ExecuteOrderEvent(
            order_id=701, executed_qty=30, match_number=8002, price=1010000
        ),
        # 3. Non-displayed trade 'P': 50 @ 99.50
        TradeEvent(
            match_number=8003,
            side=Side.BUY,
            shares=50,
            stock="AAPL",
            price=995000,
        ),
        # 4. Broken trade 'B': breaks match 8002 (30 @ 101)
        BrokenTradeEvent(match_number=8002),
    ]


def build_scenario_h() -> list[BaseEvent]:
    """Scenario H: Invalid input handling and corruption resistance."""
    return [
        # Valid setup
        AddOrderEvent(order_id=801, side=Side.BUY, price=1000000, quantity=50),
        # 1. Duplicate order ID
        AddOrderEvent(order_id=801, side=Side.BUY, price=1000000, quantity=10),
        # 2. Unknown order ID execute
        ExecuteOrderEvent(order_id=999, executed_qty=10),
        # 3. Over-execution
        ExecuteOrderEvent(order_id=801, executed_qty=60),
        # 4. Negative/zero quantity execute
        ExecuteOrderEvent(order_id=801, executed_qty=0),
        # 5. Over-cancellation
        CancelOrderEvent(order_id=801, canceled_qty=55),
        # 6. Unknown order ID delete
        DeleteOrderEvent(order_id=999),
        # 7. Replace with existing new ID
        ReplaceOrderEvent(
            old_order_id=801,
            new_order_id=801,
            new_price=1000000,
            new_quantity=10,
        ),
    ]


SCENARIO_BUILDERS: dict[str, Callable[[], list[BaseEvent]]] = {
    "A": build_scenario_a,
    "B": build_scenario_b,
    "C": build_scenario_c,
    "D": build_scenario_d,
    "E": build_scenario_e,
    "F": build_scenario_f,
    "G": build_scenario_g,
    "H": build_scenario_h,
}


def run_scenario(name: str) -> tuple[OrderBook, list[AuditRecord]]:
    """Execute a scenario by name ('A' through 'H') and return the book and audit log."""
    builder = SCENARIO_BUILDERS.get(name.upper())
    if builder is None:
        raise ValueError(
            f"Unknown scenario {name!r}. Available: {list(SCENARIO_BUILDERS.keys())}"
        )

    book = OrderBook()
    records = book.run(builder())
    return book, records
