"""Price level representation maintaining FIFO queue and aggregated metrics."""

from __future__ import annotations

from collections import OrderedDict
from typing import Iterator

from lob_sim.models import Order, PriceLevelSummary, Side


class PriceLevel:
    """Maintains a single price level with FIFO priority among resting orders."""

    __slots__ = ("_price", "_side", "_total_quantity", "_orders")

    def __init__(self, price: int, side: Side) -> None:
        if price <= 0:
            raise ValueError(f"Price must be positive, got {price}")
        self._price: int = price
        self._side: Side = side
        self._total_quantity: int = 0
        # OrderedDict maps order_id -> Order, preserving FIFO queue insertion order
        self._orders: OrderedDict[int, Order] = OrderedDict()

    @property
    def price(self) -> int:
        return self._price

    @property
    def side(self) -> Side:
        return self._side

    @property
    def total_quantity(self) -> int:
        return self._total_quantity

    @property
    def order_count(self) -> int:
        return len(self._orders)

    def is_empty(self) -> bool:
        return len(self._orders) == 0

    def add_order(self, order: Order) -> None:
        """Enqueue an order at the tail of this price level (FIFO priority)."""
        if order.price != self._price:
            raise ValueError(
                f"Order price {order.price} does not match level price {self._price}"
            )
        if order.side != self._side:
            raise ValueError(
                f"Order side {order.side} does not match level side {self._side}"
            )
        if order.order_id in self._orders:
            raise ValueError(
                f"Duplicate order ID {order.order_id} at price level {self._price}"
            )
        if order.remaining_qty <= 0:
            raise ValueError(
                f"Cannot add order with non-positive remaining quantity {order.remaining_qty}"
            )

        self._orders[order.order_id] = order
        self._total_quantity += order.remaining_qty

    def reduce_order_qty(self, order_id: int, decrement: int) -> int:
        """Partially reduce an order's remaining quantity, preserving queue priority."""
        if decrement <= 0:
            raise ValueError(f"Reduction decrement must be positive, got {decrement}")
        if order_id not in self._orders:
            raise KeyError(f"Order ID {order_id} not found at price level {self._price}")

        order = self._orders[order_id]
        if decrement > order.remaining_qty:
            raise ValueError(
                f"Cannot reduce order {order_id} by {decrement}; only {order.remaining_qty} remaining"
            )

        order.remaining_qty -= decrement
        self._total_quantity -= decrement

        # If completely depleted by cancellation/reduction, remove it
        if order.remaining_qty == 0:
            del self._orders[order_id]

        return order.remaining_qty

    def remove_order(self, order_id: int) -> Order:
        """Remove an order completely from this price level."""
        if order_id not in self._orders:
            raise KeyError(f"Order ID {order_id} not found at price level {self._price}")

        order = self._orders.pop(order_id)
        self._total_quantity -= order.remaining_qty
        return order

    def get_order(self, order_id: int) -> Order | None:
        return self._orders.get(order_id)

    def __iter__(self) -> Iterator[Order]:
        """Iterate orders in FIFO queue sequence."""
        return iter(self._orders.values())

    def orders_list(self) -> list[Order]:
        """Return a snapshot list of orders in queue order."""
        return list(self._orders.values())

    def summary(self) -> PriceLevelSummary:
        return PriceLevelSummary(
            price=self._price,
            total_quantity=self._total_quantity,
            order_count=len(self._orders),
        )

    def __repr__(self) -> str:
        return (
            f"PriceLevel(price={self._price}, side={self._side}, "
            f"orders={len(self._orders)}, qty={self._total_quantity})"
        )
