"""Property-based differential testing between OrderBook and NaiveReferenceModel."""

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
from lob_sim.reference_model import NaiveReferenceModel


@settings(max_examples=100, deadline=None)
@given(
    events=st.lists(
        st.one_of(
            st.builds(
                AddOrderEvent,
                order_id=st.integers(min_value=1, max_value=25),
                side=st.sampled_from([Side.BUY, Side.SELL]),
                price=st.integers(min_value=950000, max_value=1050000),
                quantity=st.integers(min_value=1, max_value=50),
            ),
            st.builds(
                ExecuteOrderEvent,
                order_id=st.integers(min_value=1, max_value=25),
                executed_qty=st.integers(min_value=1, max_value=50),
            ),
            st.builds(
                CancelOrderEvent,
                order_id=st.integers(min_value=1, max_value=25),
                canceled_qty=st.integers(min_value=1, max_value=50),
            ),
            st.builds(
                DeleteOrderEvent,
                order_id=st.integers(min_value=1, max_value=25),
            ),
        ),
        min_size=1,
        max_size=40,
    )
)
def test_differential_equivalence_against_naive_model(events):
    book = OrderBook()
    naive = NaiveReferenceModel()

    for ev in events:
        rec = book.step(ev)
        naive_ok = naive.step(ev)

        assert rec.success == naive_ok, (
            f"Model disagreement on {ev}: OrderBook={rec.success} (err={rec.error_message}), "
            f"Naive={naive_ok}"
        )

        tob_book = book.get_tob()
        tob_naive = naive.get_tob()

        assert tob_book.best_bid_price == tob_naive.best_bid_price
        assert tob_book.best_bid_qty == tob_naive.best_bid_qty
        assert tob_book.best_ask_price == tob_naive.best_ask_price
        assert tob_book.best_ask_qty == tob_naive.best_ask_qty
        assert tob_book.spread == tob_naive.spread
        assert tob_book.midpoint == tob_naive.midpoint
        assert book.cumulative_volume == naive.cumulative_volume
        assert book.trade_count == naive.trade_count
