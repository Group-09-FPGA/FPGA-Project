"""Unit tests for PriceLevel queue operations and invariant preservation."""

import pytest
from lob_sim.models import Order, Side
from lob_sim.price_levels import PriceLevel


def test_price_level_initialization():
    level = PriceLevel(1000000, Side.BUY)
    assert level.price == 1000000
    assert level.side == Side.BUY
    assert level.total_quantity == 0
    assert level.order_count == 0
    assert level.is_empty()


def test_price_level_invalid_init():
    with pytest.raises(ValueError):
        PriceLevel(0, Side.BUY)
    with pytest.raises(ValueError):
        PriceLevel(-100, Side.SELL)


def test_add_orders_fifo_priority():
    level = PriceLevel(1000000, Side.BUY)
    o1 = Order(1, Side.BUY, 1000000, 10, 10)
    o2 = Order(2, Side.BUY, 1000000, 20, 20)

    level.add_order(o1)
    level.add_order(o2)

    assert level.total_quantity == 30
    assert level.order_count == 2
    assert not level.is_empty()

    # FIFO iteration
    orders = list(level)
    assert len(orders) == 2
    assert orders[0].order_id == 1
    assert orders[1].order_id == 2


def test_reduce_order_quantity():
    level = PriceLevel(1000000, Side.BUY)
    o1 = Order(1, Side.BUY, 1000000, 50, 50)
    level.add_order(o1)

    rem = level.reduce_order_qty(1, 20)
    assert rem == 30
    assert level.total_quantity == 30
    assert level.order_count == 1

    # Over-reduction should fail
    with pytest.raises(ValueError):
        level.reduce_order_qty(1, 35)

    # Full reduction removes order
    rem2 = level.reduce_order_qty(1, 30)
    assert rem2 == 0
    assert level.total_quantity == 0
    assert level.order_count == 0
    assert level.is_empty()


def test_remove_order():
    level = PriceLevel(1000000, Side.BUY)
    o1 = Order(1, Side.BUY, 1000000, 10, 10)
    o2 = Order(2, Side.BUY, 1000000, 20, 20)
    level.add_order(o1)
    level.add_order(o2)

    removed = level.remove_order(1)
    assert removed.order_id == 1
    assert level.total_quantity == 20
    assert level.order_count == 1
    assert level.orders_list()[0].order_id == 2
