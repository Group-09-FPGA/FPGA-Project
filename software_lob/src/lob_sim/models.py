"""Core domain models, enums, and dataclasses for the Limit Order Book."""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum


class Side(Enum):
    """Order side: BUY (Bid) or SELL (Ask)."""

    BUY = "BUY"
    SELL = "SELL"

    @classmethod
    def from_itch_char(cls, char: str) -> Side:
        """Parse from ITCH protocol character ('B' or 'S')."""
        if char == "B":
            return cls.BUY
        if char == "S":
            return cls.SELL
        raise ValueError(f"Invalid ITCH side character: {char!r}")

    def to_itch_char(self) -> str:
        """Convert to ITCH protocol character ('B' or 'S')."""
        return "B" if self == Side.BUY else "S"

    def __str__(self) -> str:
        return self.value


class OrderStatus(Enum):
    """Lifecycle status of an individual order."""

    ACTIVE = "ACTIVE"
    PARTIALLY_FILLED = "PARTIALLY_FILLED"
    FILLED = "FILLED"
    CANCELLED = "CANCELLED"


class RecoveryState(Enum):
    """Transport sequence receiver state."""

    SEQUENCED = "SEQUENCED"
    GAP_DETECTED = "GAP_DETECTED"
    RECOVERING = "RECOVERING"
    INVALID = "INVALID"


@dataclass(slots=True)
class Order:
    """An individual resting limit order record."""

    order_id: int
    side: Side
    price: int  # Unsigned integer price (fixed-point 4 decimal places)
    original_qty: int
    remaining_qty: int
    executed_qty: int = 0
    timestamp_ns: int = 0
    mpid: str | None = None

    @property
    def status(self) -> OrderStatus:
        """Derive order status from quantities."""
        if self.remaining_qty == 0:
            return OrderStatus.FILLED
        if self.executed_qty > 0:
            return OrderStatus.PARTIALLY_FILLED
        return OrderStatus.ACTIVE

    def copy(self) -> Order:
        """Return an exact copy of the order record."""
        return Order(
            order_id=self.order_id,
            side=self.side,
            price=self.price,
            original_qty=self.original_qty,
            remaining_qty=self.remaining_qty,
            executed_qty=self.executed_qty,
            timestamp_ns=self.timestamp_ns,
            mpid=self.mpid,
        )


@dataclass(frozen=True, slots=True)
class PriceLevelSummary:
    """Aggregated state of a single price level."""

    price: int
    total_quantity: int
    order_count: int


@dataclass(frozen=True, slots=True)
class TOBSnapshot:
    """Top-of-Book (BBO) snapshot at an instant in time."""

    best_bid_price: int | None
    best_bid_qty: int
    best_ask_price: int | None
    best_ask_qty: int
    spread: int | None
    midpoint: int | None
    is_locked: bool
    is_crossed: bool


@dataclass(frozen=True, slots=True)
class TradeExecutionRecord:
    """Audit record of an executed trade."""

    match_number: int
    order_id: int | None
    side: Side | None
    price: int
    quantity: int
    timestamp_ns: int
    is_printable: bool = True


@dataclass(frozen=True, slots=True)
class BookInvariants:
    """Result of invariant consistency check."""

    is_valid: bool
    active_order_count: int
    bid_levels_count: int
    ask_levels_count: int
    total_bid_quantity: int
    total_ask_quantity: int
    violations: tuple[str, ...]
