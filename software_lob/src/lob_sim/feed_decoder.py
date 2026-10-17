"""NASDAQ TotalView-ITCH 5.0 binary message decoder and encoder."""

from __future__ import annotations

import struct
from typing import NamedTuple

from lob_sim.events import (
    AddOrderEvent,
    BaseEvent,
    BrokenTradeEvent,
    CancelOrderEvent,
    DeleteOrderEvent,
    ExecuteOrderEvent,
    ReplaceOrderEvent,
    SystemEvent,
    TradeEvent,
    TradingActionEvent,
)
from lob_sim.models import Side


class DecodedMessage(NamedTuple):
    """Container for raw decoded ITCH message fields."""

    msg_type: str
    stock_locate: int
    tracking_number: int
    timestamp_ns: int
    event: BaseEvent
    raw_bytes: bytes


class ITCHDecoder:
    """Decoder and encoder for NASDAQ TotalView-ITCH 5.0 binary protocol."""

    # Fixed lengths for ITCH 5.0 message types
    MESSAGE_LENGTHS: dict[str, int] = {
        "S": 12,  # System Event
        "R": 39,  # Stock Directory
        "H": 25,  # Stock Trading Action
        "A": 36,  # Add Order No MPID
        "F": 40,  # Add Order With MPID
        "E": 31,  # Order Executed
        "C": 36,  # Order Executed with Price
        "X": 23,  # Order Cancel
        "D": 19,  # Order Delete
        "U": 35,  # Order Replace
        "P": 44,  # Trade Message (Non-Cross)
        "Q": 40,  # Cross Trade
        "B": 19,  # Broken Trade
    }

    @classmethod
    def decode_message(cls, data: bytes) -> DecodedMessage:
        """Decode a single ITCH 5.0 binary message payload."""
        if not data:
            raise ValueError("Empty binary data")

        msg_type = chr(data[0])
        expected_len = cls.MESSAGE_LENGTHS.get(msg_type)
        if expected_len is None:
            raise ValueError(f"Unknown ITCH 5.0 message type: {msg_type!r}")
        if len(data) < expected_len:
            raise ValueError(
                f"Truncated ITCH message type {msg_type!r}: expected {expected_len} bytes, got {len(data)}"
            )

        # Standard header (bytes 1..10)
        stock_locate = int.from_bytes(data[1:3], byteorder="big")
        tracking_number = int.from_bytes(data[3:5], byteorder="big")
        timestamp_ns = int.from_bytes(data[5:11], byteorder="big")

        payload = data[:expected_len]

        event: BaseEvent
        match msg_type:
            case "A":  # Add Order No MPID (36B)
                order_ref, side_char, shares, stock_raw, price = (
                    struct.unpack_from(">QcI8sI", payload, 11)
                )
                event = AddOrderEvent(
                    timestamp_ns=timestamp_ns,
                    order_id=order_ref,
                    side=Side.from_itch_char(side_char.decode("ascii")),
                    price=price,
                    quantity=shares,
                    mpid=None,
                )

            case "F":  # Add Order With MPID (40B)
                order_ref, side_char, shares, stock_raw, price, mpid_raw = (
                    struct.unpack_from(">QcI8sI4s", payload, 11)
                )
                event = AddOrderEvent(
                    timestamp_ns=timestamp_ns,
                    order_id=order_ref,
                    side=Side.from_itch_char(side_char.decode("ascii")),
                    price=price,
                    quantity=shares,
                    mpid=mpid_raw.decode("ascii").strip(),
                )

            case "E":  # Order Executed (31B)
                order_ref, shares, match_number = struct.unpack_from(
                    ">QIQ", payload, 11
                )
                event = ExecuteOrderEvent(
                    timestamp_ns=timestamp_ns,
                    order_id=order_ref,
                    executed_qty=shares,
                    match_number=match_number,
                    price=None,
                )

            case "C":  # Order Executed With Price (36B)
                (
                    order_ref,
                    shares,
                    match_number,
                    printable_char,
                    price,
                ) = struct.unpack_from(">QIQcI", payload, 11)
                event = ExecuteOrderEvent(
                    timestamp_ns=timestamp_ns,
                    order_id=order_ref,
                    executed_qty=shares,
                    match_number=match_number,
                    price=price,
                )

            case "X":  # Order Cancel (23B)
                order_ref, shares = struct.unpack_from(">QI", payload, 11)
                event = CancelOrderEvent(
                    timestamp_ns=timestamp_ns,
                    order_id=order_ref,
                    canceled_qty=shares,
                )

            case "D":  # Order Delete (19B)
                order_ref = struct.unpack_from(">Q", payload, 11)[0]
                event = DeleteOrderEvent(
                    timestamp_ns=timestamp_ns,
                    order_id=order_ref,
                )

            case "U":  # Order Replace (35B)
                orig_ref, new_ref, shares, price = struct.unpack_from(
                    ">QQII", payload, 11
                )
                event = ReplaceOrderEvent(
                    timestamp_ns=timestamp_ns,
                    old_order_id=orig_ref,
                    new_order_id=new_ref,
                    new_price=price,
                    new_quantity=shares,
                )

            case "P":  # Trade (Non-Cross) (44B)
                (
                    order_ref,
                    side_char,
                    shares,
                    stock_raw,
                    price,
                    match_number,
                ) = struct.unpack_from(">QcI8sIQ", payload, 11)
                event = TradeEvent(
                    timestamp_ns=timestamp_ns,
                    match_number=match_number,
                    side=Side.from_itch_char(side_char.decode("ascii")),
                    shares=shares,
                    stock=stock_raw.decode("ascii").strip(),
                    price=price,
                )

            case "B":  # Broken Trade (19B)
                match_number = struct.unpack_from(">Q", payload, 11)[0]
                event = BrokenTradeEvent(
                    timestamp_ns=timestamp_ns,
                    match_number=match_number,
                )

            case "S":  # System Event (12B)
                event_code = chr(payload[11])
                event = SystemEvent(
                    timestamp_ns=timestamp_ns,
                    event_code=event_code,
                )

            case "H":  # Stock Trading Action (25B)
                stock_raw, state_char, _, reason_raw = struct.unpack_from(
                    ">8scc4s", payload, 11
                )
                event = TradingActionEvent(
                    timestamp_ns=timestamp_ns,
                    stock=stock_raw.decode("ascii").strip(),
                    state=state_char.decode("ascii"),
                    reason=reason_raw.decode("ascii").strip(),
                )

            case _:
                # Other messages (e.g. 'R', 'Q') map to BaseEvent
                event = BaseEvent(timestamp_ns=timestamp_ns)

        return DecodedMessage(
            msg_type=msg_type,
            stock_locate=stock_locate,
            tracking_number=tracking_number,
            timestamp_ns=timestamp_ns,
            event=event,
            raw_bytes=payload,
        )

    # -------------------------------------------------------------------------
    # Binary Encoders (for test vectors, test fixtures, and RTL testbenches)
    # -------------------------------------------------------------------------

    @classmethod
    def _pack_header(
        cls, msg_type: str, locate: int, tracking: int, timestamp_ns: int
    ) -> bytes:
        ts_bytes = timestamp_ns.to_bytes(6, byteorder="big")
        return (
            msg_type.encode("ascii")
            + locate.to_bytes(2, byteorder="big")
            + tracking.to_bytes(2, byteorder="big")
            + ts_bytes
        )

    @classmethod
    def encode_add_order(
        cls,
        order_id: int,
        side: Side,
        quantity: int,
        price: int,
        stock: str = "AAPL",
        locate: int = 1,
        tracking: int = 1,
        timestamp_ns: int = 0,
    ) -> bytes:
        header = cls._pack_header("A", locate, tracking, timestamp_ns)
        body = struct.pack(
            ">QcI8sI",
            order_id,
            side.to_itch_char().encode("ascii"),
            quantity,
            stock.ljust(8).encode("ascii"),
            price,
        )
        return header + body

    @classmethod
    def encode_execute_order(
        cls,
        order_id: int,
        executed_qty: int,
        match_number: int,
        locate: int = 1,
        tracking: int = 1,
        timestamp_ns: int = 0,
    ) -> bytes:
        header = cls._pack_header("E", locate, tracking, timestamp_ns)
        body = struct.pack(">QIQ", order_id, executed_qty, match_number)
        return header + body

    @classmethod
    def encode_cancel_order(
        cls,
        order_id: int,
        canceled_qty: int,
        locate: int = 1,
        tracking: int = 1,
        timestamp_ns: int = 0,
    ) -> bytes:
        header = cls._pack_header("X", locate, tracking, timestamp_ns)
        body = struct.pack(">QI", order_id, canceled_qty)
        return header + body

    @classmethod
    def encode_delete_order(
        cls,
        order_id: int,
        locate: int = 1,
        tracking: int = 1,
        timestamp_ns: int = 0,
    ) -> bytes:
        header = cls._pack_header("D", locate, tracking, timestamp_ns)
        body = struct.pack(">Q", order_id)
        return header + body

    @classmethod
    def encode_replace_order(
        cls,
        old_order_id: int,
        new_order_id: int,
        new_quantity: int,
        new_price: int,
        locate: int = 1,
        tracking: int = 1,
        timestamp_ns: int = 0,
    ) -> bytes:
        header = cls._pack_header("U", locate, tracking, timestamp_ns)
        body = struct.pack(
            ">QQII", old_order_id, new_order_id, new_quantity, new_price
        )
        return header + body
