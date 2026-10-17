"""Normalized event definitions and comprehensive audit records."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from lob_sim.models import Order, PriceLevelSummary, Side, TOBSnapshot


@dataclass(frozen=True, slots=True)
class BaseEvent:
    """Base class for all normalized internal market events."""

    timestamp_ns: int = 0


@dataclass(frozen=True, slots=True)
class AddOrderEvent(BaseEvent):
    """Add a new limit order to the book."""

    order_id: int = 0
    side: Side = Side.BUY
    price: int = 0  # 4-decimal fixed-point integer
    quantity: int = 0
    mpid: str | None = None


@dataclass(frozen=True, slots=True)
class ExecuteOrderEvent(BaseEvent):
    """Execute shares against a resting limit order."""

    order_id: int = 0
    executed_qty: int = 0
    match_number: int = 0
    price: int | None = None  # Explicit trade price if known; else resting price


@dataclass(frozen=True, slots=True)
class CancelOrderEvent(BaseEvent):
    """Partially cancel shares from an active order."""

    order_id: int = 0
    canceled_qty: int = 0


@dataclass(frozen=True, slots=True)
class DeleteOrderEvent(BaseEvent):
    """Delete an active order completely from the book."""

    order_id: int = 0


@dataclass(frozen=True, slots=True)
class ReplaceOrderEvent(BaseEvent):
    """Replace an existing order with a new order (cancels old, creates new)."""

    old_order_id: int = 0
    new_order_id: int = 0
    new_price: int = 0
    new_quantity: int = 0


@dataclass(frozen=True, slots=True)
class TradeEvent(BaseEvent):
    """Non-cross trade report (execution of non-displayed order)."""

    match_number: int = 0
    side: Side = Side.BUY
    shares: int = 0
    stock: str = ""
    price: int = 0


@dataclass(frozen=True, slots=True)
class BrokenTradeEvent(BaseEvent):
    """Report that an earlier execution match has been broken/canceled."""

    match_number: int = 0


@dataclass(frozen=True, slots=True)
class SystemEvent(BaseEvent):
    """Market system event notification (e.g. start/end of hours)."""

    event_code: str = ""


@dataclass(frozen=True, slots=True)
class TradingActionEvent(BaseEvent):
    """Stock trading action event (trading, halt, pause)."""

    stock: str = ""
    state: str = ""
    reason: str = ""


@dataclass(frozen=True, slots=True)
class AuditRecord:
    """Detailed audit snapshot produced for every applied event."""

    event_number: int
    event: BaseEvent
    success: bool
    error_message: str | None
    order_before: Order | None
    order_after: Order | None
    affected_level_before: PriceLevelSummary | None
    affected_level_after: PriceLevelSummary | None
    tob_before: TOBSnapshot
    tob_after: TOBSnapshot
    cumulative_volume_after: int
    trade_count_after: int
    explanation: str

    def to_dict(self) -> dict[str, Any]:
        """Convert audit record to a JSON-serializable dictionary."""
        return {
            "event_number": self.event_number,
            "event_type": type(self.event).__name__,
            "success": self.success,
            "error_message": self.error_message,
            "order_before": (
                {
                    "order_id": self.order_before.order_id,
                    "side": self.order_before.side.value,
                    "price": self.order_before.price,
                    "remaining_qty": self.order_before.remaining_qty,
                }
                if self.order_before
                else None
            ),
            "order_after": (
                {
                    "order_id": self.order_after.order_id,
                    "side": self.order_after.side.value,
                    "price": self.order_after.price,
                    "remaining_qty": self.order_after.remaining_qty,
                }
                if self.order_after
                else None
            ),
            "tob_before": {
                "best_bid_price": self.tob_before.best_bid_price,
                "best_bid_qty": self.tob_before.best_bid_qty,
                "best_ask_price": self.tob_before.best_ask_price,
                "best_ask_qty": self.tob_before.best_ask_qty,
                "spread": self.tob_before.spread,
                "midpoint": self.tob_before.midpoint,
            },
            "tob_after": {
                "best_bid_price": self.tob_after.best_bid_price,
                "best_bid_qty": self.tob_after.best_bid_qty,
                "best_ask_price": self.tob_after.best_ask_price,
                "best_ask_qty": self.tob_after.best_ask_qty,
                "spread": self.tob_after.spread,
                "midpoint": self.tob_after.midpoint,
            },
            "cumulative_volume_after": self.cumulative_volume_after,
            "trade_count_after": self.trade_count_after,
            "explanation": self.explanation,
        }
