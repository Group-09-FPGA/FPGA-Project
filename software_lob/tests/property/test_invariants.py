"""Property-based invariant testing using Hypothesis."""

from hypothesis import given, settings
from hypothesis import strategies as st
from lob_sim.events import (
    AddOrderEvent,
    CancelOrderEvent,
    DeleteOrderEvent,
    ExecuteOrderEvent,
)
from lob_sim.models import Side
from lob_sim.order_book import OrderBook


@settings(max_examples=100, deadline=None)
@given(
    events=st.lists(
        st.one_of(
            st.builds(
                AddOrderEvent,
                order_id=st.integers(min_value=1, max_value=20),
                side=st.sampled_from([Side.BUY, Side.SELL]),
                price=st.integers(min_value=900000, max_value=1100000),
                quantity=st.integers(min_value=1, max_value=100),
            ),
            st.builds(
                ExecuteOrderEvent,
                order_id=st.integers(min_value=1, max_value=20),
                executed_qty=st.integers(min_value=1, max_value=100),
            ),
            st.builds(
                CancelOrderEvent,
                order_id=st.integers(min_value=1, max_value=20),
                canceled_qty=st.integers(min_value=1, max_value=100),
            ),
            st.builds(
                DeleteOrderEvent,
                order_id=st.integers(min_value=1, max_value=20),
            ),
        ),
        min_size=1,
        max_size=50,
    )
)
def test_property_invariants_hold_under_arbitrary_events(events):
    book = OrderBook()
    for ev in events:
        book.step(ev)
        inv = book.check_invariants()
        assert inv.is_valid, f"Violations after {ev}: {inv.violations}"
