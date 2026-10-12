"""Automated verification of worked Scenarios A through H from specification."""

from lob_sim.scenarios import run_scenario


def test_scenario_a_add_orders():
    book, records = run_scenario("A")
    assert all(r.success for r in records)
    assert book.order_count == 4

    tob = book.get_tob()
    assert tob.best_bid_price == 1000000  # ₹100.00
    assert tob.best_bid_qty == 50
    assert tob.best_ask_price == 1020000  # ₹102.00
    assert tob.best_ask_qty == 15
    assert tob.spread == 20000  # ₹2.00
    assert tob.midpoint == 1010000  # ₹101.00

    bids_depth = book.get_bids_depth(5)
    assert len(bids_depth) == 2
    assert bids_depth[0].price == 1000000
    assert bids_depth[0].total_quantity == 50
    assert bids_depth[1].price == 990000
    assert bids_depth[1].total_quantity == 30

    asks_depth = book.get_asks_depth(5)
    assert len(asks_depth) == 2
    assert asks_depth[0].price == 1020000
    assert asks_depth[0].total_quantity == 15
    assert asks_depth[1].price == 1030000
    assert asks_depth[1].total_quantity == 20

    assert book.check_invariants().is_valid


def test_scenario_b_executions():
    book, records = run_scenario("B")
    assert all(r.success for r in records)
    # 50 shares executed in two chunks (20 and 30) -> order filled and book empty
    assert book.order_count == 0
    assert book.cumulative_volume == 50
    assert book.trade_count == 2
    assert book.get_tob().best_bid_price is None
    assert book.check_invariants().is_valid


def test_scenario_c_cancellation_and_deletion():
    book, records = run_scenario("C")
    assert all(r.success for r in records)
    assert book.order_count == 0
    assert book.get_tob().best_bid_price is None
    assert book.check_invariants().is_valid


def test_scenario_d_tob_dynamics():
    book, records = run_scenario("D")
    assert all(r.success for r in records)
    # Final state has one bid (406 @ 1005000, 40 shares) and one ask (404 @ 1030000, 25 shares)
    tob = book.get_tob()
    assert tob.best_bid_price == 1005000
    assert tob.best_bid_qty == 40
    assert tob.best_ask_price == 1030000
    assert tob.best_ask_qty == 25
    assert book.check_invariants().is_valid


def test_scenario_e_price_time_priority():
    book, records = run_scenario("E")
    assert all(r.success for r in records)
    # Orders 502 (B: 20) and 503 (C: 30) remain at 1000000
    assert book.order_count == 2
    level = book._bids[1000000]
    queue_ids = [o.order_id for o in level]
    # Priority order must be B (502), then C (503)
    assert queue_ids == [502, 503]
    assert book.check_invariants().is_valid


def test_scenario_f_order_replace():
    book, records = run_scenario("F")
    assert all(r.success for r in records)
    assert book.order_count == 2
    # 604 at 1010000 (30 shares) and 602 at 1000000 (25 shares)
    tob = book.get_tob()
    assert tob.best_bid_price == 1010000
    assert tob.best_bid_qty == 30
    assert book.check_invariants().is_valid


def test_scenario_g_trade_reporting_and_vwap():
    book, records = run_scenario("G")
    assert all(r.success for r in records)
    # Trade 1: 40 @ 1000000 = 40,000,000
    # Trade 2: 30 @ 1010000 = 30,300,000 (Broken later!)
    # Trade 3: 50 @ 995000 = 49,750,000
    # After BrokenTrade(8002):
    # Active trades: Trade 1 (40) + Trade 3 (50) = 90 shares
    # Notional: 40,000,000 + 49,750,000 = 89,750,000
    # VWAP = 89,750,000 / 90 = 997,222.222...
    assert book.cumulative_volume == 90
    assert book.trade_count == 2
    stats = book.get_statistics()
    assert abs(stats.vwap - (89750000 / 90)) < 1e-4
    assert book.check_invariants().is_valid


def test_scenario_h_invalid_handling():
    book, records = run_scenario("H")
    # First record (valid Add) succeeds; rest must fail
    assert records[0].success
    for r in records[1:]:
        assert not r.success
        assert r.error_message is not None

    # Book must still be intact
    assert book.order_count == 1
    assert book.get_order(801).remaining_qty == 50
    assert book.check_invariants().is_valid
