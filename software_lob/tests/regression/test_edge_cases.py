"""Regression and edge-case tests for boundary conditions and defensive handling."""

from lob_sim.events import AddOrderEvent
from lob_sim.feed_decoder import ITCHDecoder
from lob_sim.models import Side
from lob_sim.order_book import OrderBook


def test_crossed_and_locked_market_detection():
    book = OrderBook()
    # Add Ask @ 100
    book.step(
        AddOrderEvent(order_id=1, side=Side.SELL, price=1000000, quantity=10)
    )
    # Add Bid @ 100 -> Locked market
    book.step(
        AddOrderEvent(order_id=2, side=Side.BUY, price=1000000, quantity=10)
    )
    tob_locked = book.get_tob()
    assert tob_locked.is_locked
    assert not tob_locked.is_crossed
    assert tob_locked.spread == 0

    # Add Bid @ 101 -> Crossed market
    book.step(
        AddOrderEvent(order_id=3, side=Side.BUY, price=1010000, quantity=10)
    )
    tob_crossed = book.get_tob()
    assert tob_crossed.is_crossed
    assert not tob_crossed.is_locked
    assert tob_crossed.spread == -10000  # Negative spread


def test_48_bit_timestamp_boundary():
    book = OrderBook()
    # Max nanoseconds in a 24-hr trading day: 86,400,000,000,000
    max_ts = 86_400_000_000_000
    rec = book.step(
        AddOrderEvent(
            order_id=10,
            side=Side.BUY,
            price=1000000,
            quantity=100,
            timestamp_ns=max_ts,
        )
    )
    assert rec.success
    order = book.get_order(10)
    assert order.timestamp_ns == max_ts

    encoded = ITCHDecoder.encode_add_order(
        order_id=10,
        side=Side.BUY,
        quantity=100,
        price=1000000,
        timestamp_ns=max_ts,
    )
    decoded = ITCHDecoder.decode_message(encoded)
    assert decoded.timestamp_ns == max_ts
