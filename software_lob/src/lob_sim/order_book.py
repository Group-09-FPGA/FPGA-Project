"""Deterministic Limit Order Book (LOB) core engine and reference model."""

from __future__ import annotations

from collections import defaultdict
from typing import Sequence

from sortedcontainers import SortedDict

from lob_sim.events import (
    AddOrderEvent,
    AuditRecord,
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
from lob_sim.models import (
    BookInvariants,
    Order,
    PriceLevelSummary,
    Side,
    TOBSnapshot,
    TradeExecutionRecord,
)
from lob_sim.price_levels import PriceLevel
from lob_sim.statistics import (
    MarketStatistics,
    calculate_depth_quantity,
    calculate_depth_weighted_imbalance,
    calculate_midpoint,
    calculate_spread,
    calculate_spread_ticks,
    calculate_tob_imbalance,
    calculate_vwap,
)


class OrderBook:
    """Core Limit Order Book maintaining L3 order details and L2 price aggregates."""

    def __init__(self, symbol: str = "AAPL") -> None:
        self.symbol: str = symbol
        self._orders: dict[int, Order] = {}
        self._order_to_level: dict[int, PriceLevel] = {}

        # SortedDict: bids sorted ascending by price (max price is last element)
        self._bids: SortedDict[int, PriceLevel] = SortedDict()
        # SortedDict: asks sorted ascending by price (min price is first element)
        self._asks: SortedDict[int, PriceLevel] = SortedDict()

        # Trade and execution statistics
        self._trades: list[TradeExecutionRecord] = []
        self._cumulative_volume: int = 0
        self._trade_count: int = 0
        self._sum_notional: int = 0
        self._volume_at_price: defaultdict[int, int] = defaultdict(int)
        self._last_trade_price: int | None = None

        # Order-flow event counters
        self._adds_count: int = 0
        self._cancels_count: int = 0
        self._deletes_count: int = 0
        self._executes_count: int = 0
        self._replaces_count: int = 0

        # Event audit log & sequence tracking
        self._event_sequence: int = 0
        self._audit_log: list[AuditRecord] = []
        self._is_valid: bool = True

    @property
    def is_valid(self) -> bool:
        return self._is_valid

    @is_valid.setter
    def is_valid(self, value: bool) -> None:
        self._is_valid = value

    @property
    def order_count(self) -> int:
        return len(self._orders)

    @property
    def cumulative_volume(self) -> int:
        return self._cumulative_volume

    @property
    def trade_count(self) -> int:
        return self._trade_count

    def get_order(self, order_id: int) -> Order | None:
        return self._orders.get(order_id)

    def get_tob(self) -> TOBSnapshot:
        """Extract current Top-of-Book (BBO) snapshot."""
        best_bid_price: int | None = (
            self._bids.peekitem(-1)[0] if self._bids else None
        )
        best_bid_qty: int = (
            self._bids.peekitem(-1)[1].total_quantity if self._bids else 0
        )

        best_ask_price: int | None = (
            self._asks.peekitem(0)[0] if self._asks else None
        )
        best_ask_qty: int = (
            self._asks.peekitem(0)[1].total_quantity if self._asks else 0
        )

        spread = calculate_spread(best_bid_price, best_ask_price)
        midpoint = calculate_midpoint(best_bid_price, best_ask_price)

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

    def get_bids_depth(self, n: int = 5) -> list[PriceLevelSummary]:
        """Return top N bid levels in descending price order."""
        if not self._bids:
            return []
        # Keys in self._bids are ascending; reverse for bids
        items = list(self._bids.items())[::-1]
        return [lvl.summary() for _, lvl in items[:n]]

    def get_asks_depth(self, n: int = 5) -> list[PriceLevelSummary]:
        """Return top N ask levels in ascending price order."""
        if not self._asks:
            return []
        items = list(self._asks.items())
        return [lvl.summary() for _, lvl in items[:n]]

    def get_statistics(self, tick_size: int = 100) -> MarketStatistics:
        """Calculate complete market statistics snapshot."""
        tob = self.get_tob()
        bid_summaries = self.get_bids_depth(10)
        ask_summaries = self.get_asks_depth(10)

        spread_ticks = calculate_spread_ticks(
            tob.best_bid_price, tob.best_ask_price, tick_size
        )
        imbalance = calculate_tob_imbalance(tob.best_bid_qty, tob.best_ask_qty)
        dwi_5 = calculate_depth_weighted_imbalance(
            bid_summaries, ask_summaries, n_levels=5
        )
        vwap = calculate_vwap(self._sum_notional, self._cumulative_volume)

        return MarketStatistics(
            tob=tob,
            spread_ticks=spread_ticks,
            tob_imbalance=imbalance,
            depth_bid_1=calculate_depth_quantity(bid_summaries, 1),
            depth_ask_1=calculate_depth_quantity(ask_summaries, 1),
            depth_bid_5=calculate_depth_quantity(bid_summaries, 5),
            depth_ask_5=calculate_depth_quantity(ask_summaries, 5),
            depth_bid_10=calculate_depth_quantity(bid_summaries, 10),
            depth_ask_10=calculate_depth_quantity(ask_summaries, 10),
            depth_weighted_imbalance_5=dwi_5,
            cumulative_volume=self._cumulative_volume,
            trade_count=self._trade_count,
            last_trade_price=self._last_trade_price,
            vwap=vwap,
            adds_count=self._adds_count,
            cancels_count=self._cancels_count,
            deletes_count=self._deletes_count,
            executes_count=self._executes_count,
            replaces_count=self._replaces_count,
        )

    def check_invariants(self) -> BookInvariants:
        """Thoroughly audit book structural and mathematical invariants."""
        violations: list[str] = []

        total_bid_qty = 0
        total_ask_qty = 0
        active_orders_found = 0

        # Check bids
        prev_bid_price: int | None = None
        for price, level in reversed(list(self._bids.items())):
            if prev_bid_price is not None and price >= prev_bid_price:
                violations.append(
                    f"Bid ordering violation: {price} not strictly less than {prev_bid_price}"
                )
            prev_bid_price = price

            if level.is_empty():
                violations.append(
                    f"Empty bid level {price} should have been pruned"
                )

            level_qty = 0
            for order in level:
                active_orders_found += 1
                if order.remaining_qty <= 0:
                    violations.append(
                        f"Order {order.order_id} has non-positive remaining qty: {order.remaining_qty}"
                    )
                if order.price != price:
                    violations.append(
                        f"Order {order.order_id} price {order.price} != level price {price}"
                    )
                if order.side != Side.BUY:
                    violations.append(
                        f"Order {order.order_id} side {order.side} != BUY on bid side"
                    )
                if self._orders.get(order.order_id) is not order:
                    violations.append(
                        f"Order {order.order_id} in level not matching global order map"
                    )
                level_qty += order.remaining_qty

            if level_qty != level.total_quantity:
                violations.append(
                    f"Bid level {price} aggregate qty {level.total_quantity} != sum of orders {level_qty}"
                )
            total_bid_qty += level_qty

        # Check asks
        prev_ask_price: int | None = None
        for price, level in self._asks.items():
            if prev_ask_price is not None and price <= prev_ask_price:
                violations.append(
                    f"Ask ordering violation: {price} not strictly greater than {prev_ask_price}"
                )
            prev_ask_price = price

            if level.is_empty():
                violations.append(
                    f"Empty ask level {price} should have been pruned"
                )

            level_qty = 0
            for order in level:
                active_orders_found += 1
                if order.remaining_qty <= 0:
                    violations.append(
                        f"Order {order.order_id} has non-positive remaining qty: {order.remaining_qty}"
                    )
                if order.price != price:
                    violations.append(
                        f"Order {order.order_id} price {order.price} != level price {price}"
                    )
                if order.side != Side.SELL:
                    violations.append(
                        f"Order {order.order_id} side {order.side} != SELL on ask side"
                    )
                if self._orders.get(order.order_id) is not order:
                    violations.append(
                        f"Order {order.order_id} in level not matching global order map"
                    )
                level_qty += order.remaining_qty

            if level_qty != level.total_quantity:
                violations.append(
                    f"Ask level {price} aggregate qty {level.total_quantity} != sum of orders {level_qty}"
                )
            total_ask_qty += level_qty

        # Verify global order map matches count
        if len(self._orders) != active_orders_found:
            violations.append(
                f"Global order map count ({len(self._orders)}) != level orders ({active_orders_found})"
            )

        # Check Top of Book
        tob = self.get_tob()
        if self._bids and tob.best_bid_price != self._bids.peekitem(-1)[0]:
            violations.append(
                f"TOB best bid price {tob.best_bid_price} != max bid level {self._bids.peekitem(-1)[0]}"
            )
        if self._asks and tob.best_ask_price != self._asks.peekitem(0)[0]:
            violations.append(
                f"TOB best ask price {tob.best_ask_price} != min ask level {self._asks.peekitem(0)[0]}"
            )

        return BookInvariants(
            is_valid=len(violations) == 0,
            active_order_count=len(self._orders),
            bid_levels_count=len(self._bids),
            ask_levels_count=len(self._asks),
            total_bid_quantity=total_bid_qty,
            total_ask_quantity=total_ask_qty,
            violations=tuple(violations),
        )

    def step(self, event: BaseEvent) -> AuditRecord:
        """Apply exactly one event deterministically and produce an AuditRecord."""
        self._event_sequence += 1
        seq = self._event_sequence

        tob_before = self.get_tob()

        match event:
            case AddOrderEvent():
                return self._apply_add_order(seq, event, tob_before)
            case ExecuteOrderEvent():
                return self._apply_execute_order(seq, event, tob_before)
            case CancelOrderEvent():
                return self._apply_cancel_order(seq, event, tob_before)
            case DeleteOrderEvent():
                return self._apply_delete_order(seq, event, tob_before)
            case ReplaceOrderEvent():
                return self._apply_replace_order(seq, event, tob_before)
            case TradeEvent():
                return self._apply_trade_event(seq, event, tob_before)
            case BrokenTradeEvent():
                return self._apply_broken_trade(seq, event, tob_before)
            case SystemEvent():
                return self._apply_system_event(seq, event, tob_before)
            case TradingActionEvent():
                return self._apply_trading_action(seq, event, tob_before)
            case _:
                return AuditRecord(
                    event_number=seq,
                    event=event,
                    success=False,
                    error_message=f"Unsupported event type: {type(event).__name__}",
                    order_before=None,
                    order_after=None,
                    affected_level_before=None,
                    affected_level_after=None,
                    tob_before=tob_before,
                    tob_after=tob_before,
                    cumulative_volume_after=self._cumulative_volume,
                    trade_count_after=self._trade_count,
                    explanation=f"Rejected unknown event {type(event).__name__}",
                )

    def run(self, events: Sequence[BaseEvent]) -> list[AuditRecord]:
        """Apply a sequence of events, returning audit records for all steps."""
        records: list[AuditRecord] = []
        for event in events:
            records.append(self.step(event))
        return records

    # -------------------------------------------------------------------------
    # Internal Event Application Logic
    # -------------------------------------------------------------------------

    def _apply_add_order(
        self, seq: int, event: AddOrderEvent, tob_before: TOBSnapshot
    ) -> AuditRecord:
        # Input validation
        if event.order_id <= 0:
            return self._fail_audit(
                seq, event, tob_before, f"Order ID must be positive: {event.order_id}"
            )
        if event.order_id in self._orders:
            return self._fail_audit(
                seq,
                event,
                tob_before,
                f"Duplicate Order ID {event.order_id} already exists in book",
            )
        if event.price <= 0:
            return self._fail_audit(
                seq, event, tob_before, f"Order price must be positive: {event.price}"
            )
        if event.quantity <= 0:
            return self._fail_audit(
                seq,
                event,
                tob_before,
                f"Order quantity must be positive: {event.quantity}",
            )

        side_map = self._bids if event.side == Side.BUY else self._asks
        level = side_map.get(event.price)
        lvl_before = level.summary() if level else None

        # Create Order
        new_order = Order(
            order_id=event.order_id,
            side=event.side,
            price=event.price,
            original_qty=event.quantity,
            remaining_qty=event.quantity,
            timestamp_ns=event.timestamp_ns,
            mpid=event.mpid,
        )

        if level is None:
            level = PriceLevel(event.price, event.side)
            side_map[event.price] = level

        level.add_order(new_order)
        self._orders[event.order_id] = new_order
        self._order_to_level[event.order_id] = level
        self._adds_count += 1

        tob_after = self.get_tob()
        lvl_after = level.summary()

        explanation = (
            f"Added {event.side.value} Order {event.order_id}: "
            f"{event.quantity} shares @ {event.price / 10000:.4f}. "
            f"Level total shares is now {lvl_after.total_quantity} across {lvl_after.order_count} orders."
        )

        return AuditRecord(
            event_number=seq,
            event=event,
            success=True,
            error_message=None,
            order_before=None,
            order_after=new_order.copy(),
            affected_level_before=lvl_before,
            affected_level_after=lvl_after,
            tob_before=tob_before,
            tob_after=tob_after,
            cumulative_volume_after=self._cumulative_volume,
            trade_count_after=self._trade_count,
            explanation=explanation,
        )

    def _apply_execute_order(
        self, seq: int, event: ExecuteOrderEvent, tob_before: TOBSnapshot
    ) -> AuditRecord:
        if event.order_id not in self._orders:
            return self._fail_audit(
                seq,
                event,
                tob_before,
                f"Unknown Order ID {event.order_id} for execution",
            )
        if event.executed_qty <= 0:
            return self._fail_audit(
                seq,
                event,
                tob_before,
                f"Executed quantity must be positive: {event.executed_qty}",
            )

        order = self._orders[event.order_id]
        if event.executed_qty > order.remaining_qty:
            return self._fail_audit(
                seq,
                event,
                tob_before,
                f"Execution quantity {event.executed_qty} exceeds order {event.order_id} remaining qty {order.remaining_qty}",
            )

        order_before = order.copy()
        level = self._order_to_level[event.order_id]
        lvl_before = level.summary()

        # Update order & level
        order.executed_qty += event.executed_qty
        new_rem = level.reduce_order_qty(event.order_id, event.executed_qty)

        # Update trade statistics
        exec_price = event.price if event.price is not None else order.price
        self._cumulative_volume += event.executed_qty
        self._trade_count += 1
        self._last_trade_price = exec_price
        self._sum_notional += exec_price * event.executed_qty
        self._volume_at_price[exec_price] += event.executed_qty
        self._executes_count += 1

        self._trades.append(
            TradeExecutionRecord(
                match_number=event.match_number,
                order_id=order.order_id,
                side=order.side,
                price=exec_price,
                quantity=event.executed_qty,
                timestamp_ns=event.timestamp_ns,
            )
        )

        order_after = order.copy() if new_rem > 0 else None
        if new_rem == 0:
            del self._orders[event.order_id]
            del self._order_to_level[event.order_id]

        side_map = self._bids if order.side == Side.BUY else self._asks
        if level.is_empty():
            del side_map[order.price]
            lvl_after = None
        else:
            lvl_after = level.summary()

        tob_after = self.get_tob()

        explanation = (
            f"Executed {event.executed_qty} shares of {order.side.value} Order {order.order_id} "
            f"@ {exec_price / 10000:.4f}. "
            f"{'Order filled and deleted from book' if new_rem == 0 else f'Remaining shares = {new_rem}'}."
        )

        return AuditRecord(
            event_number=seq,
            event=event,
            success=True,
            error_message=None,
            order_before=order_before,
            order_after=order_after,
            affected_level_before=lvl_before,
            affected_level_after=lvl_after,
            tob_before=tob_before,
            tob_after=tob_after,
            cumulative_volume_after=self._cumulative_volume,
            trade_count_after=self._trade_count,
            explanation=explanation,
        )

    def _apply_cancel_order(
        self, seq: int, event: CancelOrderEvent, tob_before: TOBSnapshot
    ) -> AuditRecord:
        if event.order_id not in self._orders:
            return self._fail_audit(
                seq,
                event,
                tob_before,
                f"Unknown Order ID {event.order_id} for cancellation",
            )
        if event.canceled_qty <= 0:
            return self._fail_audit(
                seq,
                event,
                tob_before,
                f"Canceled quantity must be positive: {event.canceled_qty}",
            )

        order = self._orders[event.order_id]
        if event.canceled_qty > order.remaining_qty:
            return self._fail_audit(
                seq,
                event,
                tob_before,
                f"Cancel quantity {event.canceled_qty} exceeds remaining qty {order.remaining_qty}",
            )

        order_before = order.copy()
        level = self._order_to_level[event.order_id]
        lvl_before = level.summary()

        new_rem = level.reduce_order_qty(event.order_id, event.canceled_qty)
        self._cancels_count += 1

        order_after = order.copy() if new_rem > 0 else None
        if new_rem == 0:
            del self._orders[event.order_id]
            del self._order_to_level[event.order_id]

        side_map = self._bids if order.side == Side.BUY else self._asks
        if level.is_empty():
            del side_map[order.price]
            lvl_after = None
        else:
            lvl_after = level.summary()

        tob_after = self.get_tob()

        explanation = (
            f"Cancelled {event.canceled_qty} shares from Order {order.order_id}. "
            f"{'Order fully cancelled and deleted' if new_rem == 0 else f'Remaining shares = {new_rem}'}."
        )

        return AuditRecord(
            event_number=seq,
            event=event,
            success=True,
            error_message=None,
            order_before=order_before,
            order_after=order_after,
            affected_level_before=lvl_before,
            affected_level_after=lvl_after,
            tob_before=tob_before,
            tob_after=tob_after,
            cumulative_volume_after=self._cumulative_volume,
            trade_count_after=self._trade_count,
            explanation=explanation,
        )

    def _apply_delete_order(
        self, seq: int, event: DeleteOrderEvent, tob_before: TOBSnapshot
    ) -> AuditRecord:
        if event.order_id not in self._orders:
            return self._fail_audit(
                seq,
                event,
                tob_before,
                f"Unknown Order ID {event.order_id} for deletion",
            )

        order = self._orders[event.order_id]
        order_before = order.copy()
        level = self._order_to_level[event.order_id]
        lvl_before = level.summary()

        level.remove_order(event.order_id)
        del self._orders[event.order_id]
        del self._order_to_level[event.order_id]
        self._deletes_count += 1

        side_map = self._bids if order.side == Side.BUY else self._asks
        if level.is_empty():
            del side_map[order.price]
            lvl_after = None
        else:
            lvl_after = level.summary()

        tob_after = self.get_tob()

        explanation = (
            f"Deleted {order.side.value} Order {order.order_id} completely. "
            f"Removed {order_before.remaining_qty} remaining shares from price {order.price / 10000:.4f}."
        )

        return AuditRecord(
            event_number=seq,
            event=event,
            success=True,
            error_message=None,
            order_before=order_before,
            order_after=None,
            affected_level_before=lvl_before,
            affected_level_after=lvl_after,
            tob_before=tob_before,
            tob_after=tob_after,
            cumulative_volume_after=self._cumulative_volume,
            trade_count_after=self._trade_count,
            explanation=explanation,
        )

    def _apply_replace_order(
        self, seq: int, event: ReplaceOrderEvent, tob_before: TOBSnapshot
    ) -> AuditRecord:
        if event.old_order_id not in self._orders:
            return self._fail_audit(
                seq,
                event,
                tob_before,
                f"Unknown original Order ID {event.old_order_id} for replace",
            )
        if event.new_order_id in self._orders:
            return self._fail_audit(
                seq,
                event,
                tob_before,
                f"Replacement Order ID {event.new_order_id} already exists",
            )
        if event.new_price <= 0:
            return self._fail_audit(
                seq,
                event,
                tob_before,
                f"New price must be positive: {event.new_price}",
            )
        if event.new_quantity <= 0:
            return self._fail_audit(
                seq,
                event,
                tob_before,
                f"New quantity must be positive: {event.new_quantity}",
            )

        old_order = self._orders[event.old_order_id]
        order_before = old_order.copy()
        side = old_order.side

        # 1. Remove old order
        old_level = self._order_to_level[event.old_order_id]
        lvl_before = old_level.summary()
        old_level.remove_order(event.old_order_id)
        del self._orders[event.old_order_id]
        del self._order_to_level[event.old_order_id]

        side_map = self._bids if side == Side.BUY else self._asks
        if old_level.is_empty():
            del side_map[old_order.price]

        # 2. Insert new order
        new_order = Order(
            order_id=event.new_order_id,
            side=side,
            price=event.new_price,
            original_qty=event.new_quantity,
            remaining_qty=event.new_quantity,
            timestamp_ns=event.timestamp_ns,
        )

        new_level = side_map.get(event.new_price)
        if new_level is None:
            new_level = PriceLevel(event.new_price, side)
            side_map[event.new_price] = new_level

        new_level.add_order(new_order)
        self._orders[event.new_order_id] = new_order
        self._order_to_level[event.new_order_id] = new_level
        self._replaces_count += 1

        tob_after = self.get_tob()
        lvl_after = new_level.summary()

        explanation = (
            f"Replaced Order {event.old_order_id} with new Order {event.new_order_id}: "
            f"{event.new_quantity} shares @ {event.new_price / 10000:.4f} (new queue priority)."
        )

        return AuditRecord(
            event_number=seq,
            event=event,
            success=True,
            error_message=None,
            order_before=order_before,
            order_after=new_order.copy(),
            affected_level_before=lvl_before,
            affected_level_after=lvl_after,
            tob_before=tob_before,
            tob_after=tob_after,
            cumulative_volume_after=self._cumulative_volume,
            trade_count_after=self._trade_count,
            explanation=explanation,
        )

    def _apply_trade_event(
        self, seq: int, event: TradeEvent, tob_before: TOBSnapshot
    ) -> AuditRecord:
        if event.shares <= 0 or event.price <= 0:
            return self._fail_audit(
                seq,
                event,
                tob_before,
                f"Trade shares ({event.shares}) and price ({event.price}) must be positive",
            )

        # Trade messages for non-displayed orders update trade statistics only
        self._cumulative_volume += event.shares
        self._trade_count += 1
        self._last_trade_price = event.price
        self._sum_notional += event.price * event.shares
        self._volume_at_price[event.price] += event.shares

        self._trades.append(
            TradeExecutionRecord(
                match_number=event.match_number,
                order_id=None,
                side=event.side,
                price=event.price,
                quantity=event.shares,
                timestamp_ns=event.timestamp_ns,
            )
        )

        explanation = (
            f"Non-Cross Trade reported (Match {event.match_number}): "
            f"{event.shares} shares @ {event.price / 10000:.4f}. Displayed book unchanged."
        )

        return AuditRecord(
            event_number=seq,
            event=event,
            success=True,
            error_message=None,
            order_before=None,
            order_after=None,
            affected_level_before=None,
            affected_level_after=None,
            tob_before=tob_before,
            tob_after=tob_before,
            cumulative_volume_after=self._cumulative_volume,
            trade_count_after=self._trade_count,
            explanation=explanation,
        )

    def _apply_broken_trade(
        self, seq: int, event: BrokenTradeEvent, tob_before: TOBSnapshot
    ) -> AuditRecord:
        # Check if match_number exists in trades
        match_idx = next(
            (
                i
                for i, t in enumerate(self._trades)
                if t.match_number == event.match_number
            ),
            None,
        )

        if match_idx is not None:
            trade = self._trades.pop(match_idx)
            self._cumulative_volume -= trade.quantity
            self._trade_count -= 1
            self._sum_notional -= trade.price * trade.quantity
            self._volume_at_price[trade.price] -= trade.quantity
            explanation = (
                f"Broken Trade processed: reversed Match {event.match_number} "
                f"({trade.quantity} shares @ {trade.price / 10000:.4f})."
            )
        else:
            explanation = (
                f"Broken Trade reported for Match {event.match_number} (not found in session trade log)."
            )

        return AuditRecord(
            event_number=seq,
            event=event,
            success=True,
            error_message=None,
            order_before=None,
            order_after=None,
            affected_level_before=None,
            affected_level_after=None,
            tob_before=tob_before,
            tob_after=tob_before,
            cumulative_volume_after=self._cumulative_volume,
            trade_count_after=self._trade_count,
            explanation=explanation,
        )

    def _apply_system_event(
        self, seq: int, event: SystemEvent, tob_before: TOBSnapshot
    ) -> AuditRecord:
        explanation = f"System Event: code '{event.event_code}' processed."
        return AuditRecord(
            event_number=seq,
            event=event,
            success=True,
            error_message=None,
            order_before=None,
            order_after=None,
            affected_level_before=None,
            affected_level_after=None,
            tob_before=tob_before,
            tob_after=tob_before,
            cumulative_volume_after=self._cumulative_volume,
            trade_count_after=self._trade_count,
            explanation=explanation,
        )

    def _apply_trading_action(
        self, seq: int, event: TradingActionEvent, tob_before: TOBSnapshot
    ) -> AuditRecord:
        explanation = f"Trading Action for {event.stock}: state '{event.state}', reason: '{event.reason}'."
        return AuditRecord(
            event_number=seq,
            event=event,
            success=True,
            error_message=None,
            order_before=None,
            order_after=None,
            affected_level_before=None,
            affected_level_after=None,
            tob_before=tob_before,
            tob_after=tob_before,
            cumulative_volume_after=self._cumulative_volume,
            trade_count_after=self._trade_count,
            explanation=explanation,
        )

    def _fail_audit(
        self, seq: int, event: BaseEvent, tob: TOBSnapshot, reason: str
    ) -> AuditRecord:
        """Produce an audit record for a rejected invalid event."""
        return AuditRecord(
            event_number=seq,
            event=event,
            success=False,
            error_message=reason,
            order_before=None,
            order_after=None,
            affected_level_before=None,
            affected_level_after=None,
            tob_before=tob,
            tob_after=tob,
            cumulative_volume_after=self._cumulative_volume,
            trade_count_after=self._trade_count,
            explanation=f"REJECTED: {reason}",
        )
