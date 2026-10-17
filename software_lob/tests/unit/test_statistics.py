"""Unit tests for financial statistics and microstructure metric calculations."""

from lob_sim.models import PriceLevelSummary
from lob_sim.statistics import (
    calculate_depth_quantity,
    calculate_depth_weighted_imbalance,
    calculate_midpoint,
    calculate_spread,
    calculate_spread_ticks,
    calculate_tob_imbalance,
    calculate_vwap,
)


def test_spread_and_midpoint():
    assert calculate_spread(1000000, 1020000) == 20000
    assert calculate_spread(None, 1020000) is None
    assert calculate_spread(1000000, None) is None

    assert calculate_midpoint(1000000, 1020000) == 1010000
    assert calculate_midpoint(1000000, 1010000) == 1005000
    assert calculate_midpoint(None, 1020000) is None


def test_spread_ticks():
    # 20000 price units with 100 tick size = 200 ticks
    assert calculate_spread_ticks(1000000, 1020000, 100) == 200.0
    assert calculate_spread_ticks(None, 1020000, 100) is None


def test_tob_imbalance():
    assert calculate_tob_imbalance(50, 50) == 0.0
    assert calculate_tob_imbalance(100, 0) == 1.0
    assert calculate_tob_imbalance(0, 100) == -1.0
    assert calculate_tob_imbalance(75, 25) == 0.5
    assert calculate_tob_imbalance(0, 0) == 0.0


def test_depth_quantity():
    levels = [
        PriceLevelSummary(100, 50, 2),
        PriceLevelSummary(99, 30, 1),
        PriceLevelSummary(98, 20, 1),
    ]
    assert calculate_depth_quantity(levels, 1) == 50
    assert calculate_depth_quantity(levels, 2) == 80
    assert calculate_depth_quantity(levels, 5) == 100
    assert calculate_depth_quantity(levels, 0) == 0


def test_depth_weighted_imbalance():
    bids = [PriceLevelSummary(100, 60, 1), PriceLevelSummary(99, 40, 1)]
    asks = [PriceLevelSummary(102, 30, 1), PriceLevelSummary(103, 20, 1)]
    dwi = calculate_depth_weighted_imbalance(bids, asks, n_levels=2)
    # weighted_bid = 60/1 + 40/2 = 80
    # weighted_ask = 30/1 + 20/2 = 40
    # (80 - 40) / (80 + 40) = 40 / 120 = 1/3 ~ 0.3333333333333333
    assert abs(dwi - (1.0 / 3.0)) < 1e-9


def test_vwap():
    # Trade 1: 40 shares @ $100 -> notional 4,000
    # Trade 2: 60 shares @ $110 -> notional 6,600
    # Total notional = 10,600; Total shares = 100 -> VWAP = 106.0
    assert calculate_vwap(10600, 100) == 106.0
    assert calculate_vwap(0, 0) is None
