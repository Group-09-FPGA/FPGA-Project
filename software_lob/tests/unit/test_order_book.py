"""Unit tests for OrderBook core event processing, BBO tracking, and invariants."""

from lob_sim.events import (
    AddOrderEvent,
    CancelOrderEvent,
    DeleteOrderEvent,
    ExecuteOrderEvent,
    ReplaceOrderEvent,
)
from lob_sim.models import Side
from lob_sim.order_book import OrderBook


def test_empty_order_book():
    book = OrderBook()
    assert book.order_count == 0
    tob = book.get_tob()
    assert tob.best_bid_price is None
    assert tob.best_bid_qty == 0
    assert tob.best_ask_price is None
    assert tob.best_ask_qty == 0
    assert tob.spread is None
    assert tob.midpoint is None
    inv = book.check_invariants()
    assert inv.is_valid
    assert len(inv.violations) == 0


def test_add_order_and_tob():
    book = OrderBook()
    rec1 = book.step(
        AddOrderEvent(order_id=1, side=Side.BUY, price=1000000, quantity=50)
    )
    assert rec1.success
    assert book.order_count == 1
    tob = book.get_tob()
    assert tob.best_bid_price == 1000000
    assert tob.best_bid_qty == 50
    assert tob.best_ask_price is None

    rec2 = book.step(
        AddOrderEvent(order_id=2, side=Side.SELL, price=1020000, quantity=30)
    )
    assert rec2.success
    tob2 = book.get_tob()
    assert tob2.best_bid_price == 1000000
    assert tob2.best_bid_qty == 50
    assert tob2.best_ask_price == 1020000
    assert tob2.best_ask_qty == 30
    assert tob2.spread == 20000
    assert tob2.midpoint == 1010000
    assert not tob2.is_locked
    assert not tob2.is_crossed

    inv = book.check_invariants()
    assert inv.is_valid


def test_partial_and_full_execution():
    book = OrderBook()
    book.step(
        AddOrderEvent(order_id=101, side=Side.BUY, price=1000000, quantity=50)
    )

    # Partial execution
    rec_exec = book.step(ExecuteOrderEvent(order_id=101, executed_qty=20))
    assert rec_exec.success
    assert book.cumulative_volume == 20
    assert book.trade_count == 1
    order = book.get_order(101)
    assert order is not None
    assert order.remaining_qty == 30
    assert order.executed_qty == 20
    assert book.get_tob().best_bid_qty == 30

    # Full execution of remainder
    rec_exec2 = book.step(ExecuteOrderEvent(order_id=101, executed_qty=30))
    assert rec_exec2.success
    assert book.cumulative_volume == 50
    assert book.trade_count == 2
    assert book.get_order(101) is None
    assert book.order_count == 0
    assert book.get_tob().best_bid_price is None
    assert book.check_invariants().is_valid


def test_partial_cancel_and_delete():
    book = OrderBook()
    book.step(
        AddOrderEvent(order_id=201, side=Side.SELL, price=1050000, quantity=40)
    )

    rec_cancel = book.step(CancelOrderEvent(order_id=201, canceled_qty=15))
    assert rec_cancel.success
    assert book.get_order(201).remaining_qty == 25
    assert book.get_tob().best_ask_qty == 25

    rec_delete = book.step(DeleteOrderEvent(order_id=201))
    assert rec_delete.success
    assert book.get_order(201) is None
    assert book.get_tob().best_ask_price is None
    assert book.check_invariants().is_valid


def test_replace_order():
    book = OrderBook()
    book.step(
        AddOrderEvent(order_id=301, side=Side.BUY, price=1000000, quantity=50)
    )

    rec_replace = book.step(
        ReplaceOrderEvent(
            old_order_id=301,
            new_order_id=302,
            new_price=1010000,
            new_quantity=60,
        )
    )
    assert rec_replace.success
    assert book.get_order(301) is None
    new_order = book.get_order(302)
    assert new_order is not None
    assert new_order.price == 1010000
    assert new_order.remaining_qty == 60
    assert book.get_tob().best_bid_price == 1010000
    assert book.get_tob().best_bid_qty == 60
    assert book.check_invariants().is_valid


def test_rejection_of_invalids():
    book = OrderBook()
    book.step(
        AddOrderEvent(order_id=401, side=Side.BUY, price=1000000, quantity=50)
    )

    # Duplicate Add
    dup = book.step(
        AddOrderEvent(order_id=401, side=Side.BUY, price=1000000, quantity=20)
    )
    assert not dup.success
    assert "Duplicate Order ID" in dup.error_message

    # Unknown ID Exec
    unk_exec = book.step(ExecuteOrderEvent(order_id=999, executed_qty=10))
    assert not unk_exec.success

    # Over-exec
    over_exec = book.step(ExecuteOrderEvent(order_id=401, executed_qty=60))
    assert not over_exec.success

    # Over-cancel
    over_cancel = book.step(CancelOrderEvent(order_id=401, canceled_qty=55))
    assert not over_cancel.success

    # Book must remain completely uncorrupted
    assert book.order_count == 1
    assert book.get_order(401).remaining_qty == 50
    assert book.check_invariants().is_valid
