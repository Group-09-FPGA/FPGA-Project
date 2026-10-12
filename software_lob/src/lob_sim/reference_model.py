"""Independent, naive reference order book model for differential testing."""

from __future__ import annotations

from lob_sim.events import (
    AddOrderEvent,
    BaseEvent,
    CancelOrderEvent,
    DeleteOrderEvent,
    ExecuteOrderEvent,
    ReplaceOrderEvent,
)
from lob_sim.models import Order, Side, TOBSnapshot


class NaiveReferenceModel:
    """Deliberately simple, unoptimized order book model using raw lists.

    Used solely for differential fuzzing and cross-checking the primary OrderBook.
    """

    def __init__(self) -> None:
        self.orders: list[Order] = []
        self.cumulative_volume: int = 0
        self.trade_count: int = 0

    def step(self, event: BaseEvent) -> bool:
        """Apply an event naively. Returns True if accepted, False if rejected."""
        match event:
            case AddOrderEvent():
                if event.order_id <= 0 or event.price <= 0 or event.quantity <= 0:
                    return False
                if any(o.order_id == event.order_id for o in self.orders):
                    return False
                self.orders.append(
                    Order(
                        order_id=event.order_id,
                        side=event.side,
                        price=event.price,
                        original_qty=event.quantity,
                        remaining_qty=event.quantity,
                        timestamp_ns=event.timestamp_ns,
                    )
                )
                return True

            case ExecuteOrderEvent():
                order = next(
                    (o for o in self.orders if o.order_id == event.order_id), None
                )
                if (
                    order is None
                    or event.executed_qty <= 0
                    or event.executed_qty > order.remaining_qty
                ):
                    return False
                order.executed_qty += event.executed_qty
                order.remaining_qty -= event.executed_qty
                self.cumulative_volume += event.executed_qty
                self.trade_count += 1
                if order.remaining_qty == 0:
                    self.orders.remove(order)
                return True

            case CancelOrderEvent():
                order = next(
                    (o for o in self.orders if o.order_id == event.order_id), None
                )
                if (
                    order is None
                    or event.canceled_qty <= 0
                    or event.canceled_qty > order.remaining_qty
                ):
                    return False
                order.remaining_qty -= event.canceled_qty
                if order.remaining_qty == 0:
                    self.orders.remove(order)
                return True

            case DeleteOrderEvent():
                order = next(
                    (o for o in self.orders if o.order_id == event.order_id), None
                )
                if order is None:
                    return False
                self.orders.remove(order)
                return True

            case ReplaceOrderEvent():
                if (
                    event.new_price <= 0
                    or event.new_quantity <= 0
                    or any(o.order_id == event.new_order_id for o in self.orders)
                ):
                    return False
                old_order = next(
                    (o for o in self.orders if o.order_id == event.old_order_id),
                    None,
                )
                if old_order is None:
                    return False
                side = old_order.side
                self.orders.remove(old_order)
                self.orders.append(
                    Order(
                        order_id=event.new_order_id,
                        side=side,
                        price=event.new_price,
                        original_qty=event.new_quantity,
                        remaining_qty=event.new_quantity,
                        timestamp_ns=event.timestamp_ns,
                    )
                )
                return True

            case _:
                return True

    def get_tob(self) -> TOBSnapshot:
        """Compute BBO via linear scan over all resting orders."""
        bids = [o for o in self.orders if o.side == Side.BUY]
        asks = [o for o in self.orders if o.side == Side.SELL]

        best_bid_price = max((o.price for o in bids), default=None)
        best_bid_qty = (
            sum(o.remaining_qty for o in bids if o.price == best_bid_price)
            if best_bid_price is not None
            else 0
        )

        best_ask_price = min((o.price for o in asks), default=None)
        best_ask_qty = (
            sum(o.remaining_qty for o in asks if o.price == best_ask_price)
            if best_ask_price is not None
            else 0
        )

        spread = (
            best_ask_price - best_bid_price
            if best_bid_price is not None and best_ask_price is not None
            else None
        )
        midpoint = (
            (best_ask_price + best_bid_price) // 2
            if best_bid_price is not None and best_ask_price is not None
            else None
        )

        is_locked = (
            best_bid_price is not None
            and best_ask_price is not None
            and best_bid_price == best_ask_price
        )
        is_crossed = (
            best_bid_price is not None
            and best_ask_price is not None
            and best_bid_price > best_ask_price
        )

        return TOBSnapshot(
            best_bid_price=best_bid_price,
            best_bid_qty=best_bid_qty,
            best_ask_price=best_ask_price,
            best_ask_qty=best_ask_qty,
            spread=spread,
            midpoint=midpoint,
            is_locked=is_locked,
            is_crossed=is_crossed,
        )
