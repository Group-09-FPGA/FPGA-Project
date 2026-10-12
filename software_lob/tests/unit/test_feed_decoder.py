"""Unit tests for ITCH 5.0 binary decoding and encoding."""

import pytest
from lob_sim.events import (
    AddOrderEvent,
    CancelOrderEvent,
    DeleteOrderEvent,
    ExecuteOrderEvent,
    ReplaceOrderEvent,
)
from lob_sim.feed_decoder import ITCHDecoder
from lob_sim.models import Side


def test_decode_add_order_no_mpid():
    # 36-byte message fixture
    encoded = ITCHDecoder.encode_add_order(
        order_id=101,
        side=Side.BUY,
        quantity=50,
        price=1000000,
        stock="AAPL",
        timestamp_ns=36000000000000,
    )
    assert len(encoded) == 36
    decoded = ITCHDecoder.decode_message(encoded)
    assert decoded.msg_type == "A"
    assert decoded.timestamp_ns == 36000000000000
    assert isinstance(decoded.event, AddOrderEvent)
    assert decoded.event.order_id == 101
    assert decoded.event.side == Side.BUY
    assert decoded.event.quantity == 50
    assert decoded.event.price == 1000000
    assert decoded.event.mpid is None


def test_decode_execute_order():
    encoded = ITCHDecoder.encode_execute_order(
        order_id=101,
        executed_qty=20,
        match_number=5001,
        timestamp_ns=36000000001000,
    )
    assert len(encoded) == 31
    decoded = ITCHDecoder.decode_message(encoded)
    assert decoded.msg_type == "E"
    assert isinstance(decoded.event, ExecuteOrderEvent)
    assert decoded.event.order_id == 101
    assert decoded.event.executed_qty == 20
    assert decoded.event.match_number == 5001


def test_decode_cancel_order():
    encoded = ITCHDecoder.encode_cancel_order(
        order_id=101, canceled_qty=15
    )
    assert len(encoded) == 23
    decoded = ITCHDecoder.decode_message(encoded)
    assert decoded.msg_type == "X"
    assert isinstance(decoded.event, CancelOrderEvent)
    assert decoded.event.order_id == 101
    assert decoded.event.canceled_qty == 15


def test_decode_delete_order():
    encoded = ITCHDecoder.encode_delete_order(order_id=101)
    assert len(encoded) == 19
    decoded = ITCHDecoder.decode_message(encoded)
    assert decoded.msg_type == "D"
    assert isinstance(decoded.event, DeleteOrderEvent)
    assert decoded.event.order_id == 101


def test_decode_replace_order():
    encoded = ITCHDecoder.encode_replace_order(
        old_order_id=101,
        new_order_id=102,
        new_quantity=40,
        new_price=1010000,
    )
    assert len(encoded) == 35
    decoded = ITCHDecoder.decode_message(encoded)
    assert decoded.msg_type == "U"
    assert isinstance(decoded.event, ReplaceOrderEvent)
    assert decoded.event.old_order_id == 101
    assert decoded.event.new_order_id == 102
    assert decoded.event.new_quantity == 40
    assert decoded.event.new_price == 1010000


def test_decode_truncated_message():
    encoded = ITCHDecoder.encode_add_order(
        order_id=101, side=Side.BUY, quantity=50, price=1000000
    )
    with pytest.raises(ValueError, match="Truncated ITCH message"):
        ITCHDecoder.decode_message(encoded[:20])


def test_decode_unknown_type():
    with pytest.raises(ValueError, match="Unknown ITCH 5.0 message type"):
        ITCHDecoder.decode_message(b"Z" + b"\x00" * 30)
