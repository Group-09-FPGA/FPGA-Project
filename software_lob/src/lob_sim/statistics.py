"""Pure financial statistics, market depth, and microstructure calculations."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Sequence

from lob_sim.models import PriceLevelSummary, TOBSnapshot


@dataclass(frozen=True, slots=True)
class DepthLevel:
    """A single depth tier on one side of the order book."""

    level: int  # 1-indexed (1 is top of book)
    price: int
    quantity: int
    order_count: int


@dataclass(frozen=True, slots=True)
class MarketStatistics:
    """Comprehensive snapshot of market statistics and microstructure metrics."""

    tob: TOBSnapshot
    spread_ticks: float | None
    tob_imbalance: float
    depth_bid_1: int
    depth_ask_1: int
    depth_bid_5: int
    depth_ask_5: int
    depth_bid_10: int
    depth_ask_10: int
    depth_weighted_imbalance_5: float
    cumulative_volume: int
    trade_count: int
    last_trade_price: int | None
    vwap: float | None
    adds_count: int
    cancels_count: int
    deletes_count: int
    executes_count: int
    replaces_count: int


def calculate_spread(best_bid: int | None, best_ask: int | None) -> int | None:
    """Calculate integer bid-ask spread in price units."""
    if best_bid is None or best_ask is None:
        return None
    return best_ask - best_bid


def calculate_spread_ticks(
    best_bid: int | None, best_ask: int | None, tick_size: int
) -> float | None:
    """Calculate spread in ticks."""
    if best_bid is None or best_ask is None or tick_size <= 0:
        return None
    return (best_ask - best_bid) / tick_size


def calculate_midpoint(best_bid: int | None, best_ask: int | None) -> int | None:
    """Calculate integer midpoint (best_bid + best_ask) // 2."""
    if best_bid is None or best_ask is None:
        return None
    return (best_bid + best_ask) // 2


def calculate_tob_imbalance(bid_qty: int, ask_qty: int) -> float:
    """Calculate Top-of-Book imbalance: (bid_qty - ask_qty) / (bid_qty + ask_qty).

    Returns 0.0 when both quantities are zero.
    """
    total = bid_qty + ask_qty
    if total == 0:
        return 0.0
    return (bid_qty - ask_qty) / total


def calculate_depth_quantity(
    levels: Sequence[PriceLevelSummary], n_levels: int
) -> int:
    """Sum total displayed quantity up to n_levels deep."""
    if n_levels <= 0:
        return 0
    return sum(lvl.total_quantity for lvl in levels[:n_levels])


def calculate_depth_weighted_imbalance(
    bid_levels: Sequence[PriceLevelSummary],
    ask_levels: Sequence[PriceLevelSummary],
    n_levels: int = 5,
) -> float:
    """Calculate depth-weighted imbalance over top N levels."""
    if n_levels <= 0:
        return 0.0

    weighted_bid = sum(
        lvl.total_quantity / (k + 1)
        for k, lvl in enumerate(bid_levels[:n_levels])
    )
    weighted_ask = sum(
        lvl.total_quantity / (k + 1)
        for k, lvl in enumerate(ask_levels[:n_levels])
    )
    total_weighted = weighted_bid + weighted_ask
    if total_weighted == 0.0:
        return 0.0
    return (weighted_bid - weighted_ask) / total_weighted


def calculate_vwap(sum_notional: int, total_shares: int) -> float | None:
    """Calculate Volume-Weighted Average Price (VWAP).

    sum_notional is sum(price * shares).
    """
    if total_shares <= 0:
        return None
    return sum_notional / total_shares
