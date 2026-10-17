"""Interactive educational CLI for Limit Order Book simulation and verification."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from rich.console import Console
from rich.table import Table

from lob_sim.events import (
    AddOrderEvent,
    CancelOrderEvent,
    DeleteOrderEvent,
    ExecuteOrderEvent,
    ReplaceOrderEvent,
)
from lob_sim.models import Side
from lob_sim.order_book import OrderBook
from lob_sim.scenarios import SCENARIO_BUILDERS, run_scenario
from lob_sim.visualization import render_audit_record, render_book_ladder


def export_rtl_vectors(output_path: str = "testbench_vectors.json") -> None:
    """Generate and export deterministic test vectors for FPGA testbench verification."""
    book = OrderBook()
    vectors = []

    # Run Scenarios A through G to produce comprehensive golden vectors
    all_events = []
    for sc_name in ["A", "B", "C", "D", "E", "F", "G"]:
        all_events.extend(SCENARIO_BUILDERS[sc_name]())

    for idx, ev in enumerate(all_events, start=1):
        rec = book.step(ev)
        tob = book.get_tob()
        stats = book.get_statistics()

        ev_dict = {
            "type": type(ev).__name__,
            "timestamp_ns": ev.timestamp_ns,
        }
        if isinstance(ev, AddOrderEvent):
            ev_dict.update(
                {
                    "order_id": ev.order_id,
                    "side": ev.side.value,
                    "price": ev.price,
                    "quantity": ev.quantity,
                }
            )
        elif isinstance(ev, ExecuteOrderEvent):
            ev_dict.update(
                {
                    "order_id": ev.order_id,
                    "executed_qty": ev.executed_qty,
                    "match_number": ev.match_number,
                    "price": ev.price,
                }
            )
        elif isinstance(ev, CancelOrderEvent):
            ev_dict.update(
                {
                    "order_id": ev.order_id,
                    "canceled_qty": ev.canceled_qty,
                }
            )
        elif isinstance(ev, DeleteOrderEvent):
            ev_dict.update({"order_id": ev.order_id})
        elif isinstance(ev, ReplaceOrderEvent):
            ev_dict.update(
                {
                    "old_order_id": ev.old_order_id,
                    "new_order_id": ev.new_order_id,
                    "new_price": ev.new_price,
                    "new_quantity": ev.new_quantity,
                }
            )

        vector_step = {
            "step_index": idx,
            "input_event": ev_dict,
            "expected_state": {
                "success": rec.success,
                "active_orders": book.order_count,
                "best_bid_price": tob.best_bid_price or 0,
                "best_bid_qty": tob.best_bid_qty,
                "best_ask_price": tob.best_ask_price or 0,
                "best_ask_qty": tob.best_ask_qty,
                "spread": tob.spread or 0,
                "midpoint": tob.midpoint or 0,
                "cumulative_volume": stats.cumulative_volume,
                "trade_count": stats.trade_count,
                "is_locked": tob.is_locked,
                "is_crossed": tob.is_crossed,
                "book_valid": book.is_valid,
            },
        }
        vectors.append(vector_step)

    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(vectors, f, indent=2)

    console = Console()
    console.print(
        f"[bold green]Successfully exported {len(vectors)} RTL test vectors to {output_path}[/]"
    )


def cmd_demo(scenario: str, pause: bool, console: Console) -> None:
    """Run an educational scenario with step-by-step ladder visualization."""
    scenarios_to_run = (
        [scenario.upper()] if scenario.upper() != "ALL" else list(SCENARIO_BUILDERS.keys())
    )

    for sc in scenarios_to_run:
        console.rule(f"[bold cyan]RUNNING SCENARIO {sc}[/]")
        builder = SCENARIO_BUILDERS[sc]
        events = builder()
        book = OrderBook()

        for idx, ev in enumerate(events, start=1):
            audit = book.step(ev)
            console.print()
            render_audit_record(audit, console)
            render_book_ladder(book, console=console)

            if pause and idx < len(events):
                input("\n[Press Enter to advance to next event...]")


def cmd_stats(scenario: str, console: Console) -> None:
    """Display comprehensive statistics for a scenario."""
    book, _ = run_scenario(scenario)
    stats = book.get_statistics()

    table = Table(title=f"Market Statistics: Scenario {scenario.upper()}", style="cyan")
    table.add_column("Metric", style="bold yellow")
    table.add_column("Value", style="bold white")

    table.add_row(
        "Best Bid",
        (
            f"₹{stats.tob.best_bid_price / 10000:.4f} ({stats.tob.best_bid_qty} shares)"
            if stats.tob.best_bid_price
            else "None"
        ),
    )
    table.add_row(
        "Best Ask",
        (
            f"₹{stats.tob.best_ask_price / 10000:.4f} ({stats.tob.best_ask_qty} shares)"
            if stats.tob.best_ask_price
            else "None"
        ),
    )
    table.add_row(
        "Spread",
        (
            f"₹{stats.tob.spread / 10000:.4f} ({stats.spread_ticks:.2f} ticks)"
            if stats.tob.spread is not None and stats.spread_ticks is not None
            else "None"
        ),
    )
    table.add_row(
        "Midpoint",
        (
            f"₹{stats.tob.midpoint / 10000:.4f}"
            if stats.tob.midpoint is not None
            else "None"
        ),
    )
    table.add_row("TOB Imbalance", f"{stats.tob_imbalance:+.4f}")
    table.add_row("Depth Weighted Imbalance (L5)", f"{stats.depth_weighted_imbalance_5:+.4f}")
    table.add_row("Depth Bid (L1 / L5 / L10)", f"{stats.depth_bid_1} / {stats.depth_bid_5} / {stats.depth_bid_10}")
    table.add_row("Depth Ask (L1 / L5 / L10)", f"{stats.depth_ask_1} / {stats.depth_ask_5} / {stats.depth_ask_10}")
    table.add_row("Cumulative Traded Volume", f"{stats.cumulative_volume:,} shares")
    table.add_row("Trade Count", str(stats.trade_count))
    table.add_row(
        "Last Trade Price",
        (
            f"₹{stats.last_trade_price / 10000:.4f}"
            if stats.last_trade_price
            else "None"
        ),
    )
    table.add_row(
        "VWAP",
        f"₹{stats.vwap / 10000:.4f}" if stats.vwap is not None else "None",
    )
    table.add_row("Event Counts (Add / Cancel / Del / Exec / Rep)", f"{stats.adds_count} / {stats.cancels_count} / {stats.deletes_count} / {stats.executes_count} / {stats.replaces_count}")

    console.print(table)


def cmd_self_test(console: Console) -> None:
    """Execute test suite and display verification results."""
    import pytest

    console.print("[bold yellow]Executing full verification test suite...[/]")
    exit_code = pytest.main(["tests/", "-v", "--tb=short"])
    if exit_code == 0:
        console.print("\n[bold green]✓ ALL TESTS PASSED SUCCESSFULLY![/]")
    else:
        console.print(f"\n[bold red]✗ Test suite failed with code {exit_code}[/]")
    sys.exit(exit_code)


def cmd_run_file(file_path: str, pause: bool, console: Console) -> None:
    """Load and execute events from a JSON scenario file."""
    path = Path(file_path)
    if not path.exists():
        console.print(f"[bold red]File not found: {file_path}[/]")
        sys.exit(1)

    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)

    book = OrderBook()
    for item in data:
        ev_type = item.get("type")
        ev: BaseEvent
        match ev_type:
            case "AddOrder":
                ev = AddOrderEvent(
                    order_id=item["order_id"],
                    side=Side(item["side"]),
                    price=item["price"],
                    quantity=item["quantity"],
                    timestamp_ns=item.get("timestamp_ns", 0),
                )
            case "ExecuteOrder":
                ev = ExecuteOrderEvent(
                    order_id=item["order_id"],
                    executed_qty=item["executed_qty"],
                    match_number=item.get("match_number", 0),
                    price=item.get("price"),
                    timestamp_ns=item.get("timestamp_ns", 0),
                )
            case "CancelOrder":
                ev = CancelOrderEvent(
                    order_id=item["order_id"],
                    canceled_qty=item["canceled_qty"],
                    timestamp_ns=item.get("timestamp_ns", 0),
                )
            case "DeleteOrder":
                ev = DeleteOrderEvent(
                    order_id=item["order_id"],
                    timestamp_ns=item.get("timestamp_ns", 0),
                )
            case "ReplaceOrder":
                ev = ReplaceOrderEvent(
                    old_order_id=item["old_order_id"],
                    new_order_id=item["new_order_id"],
                    new_price=item["new_price"],
                    new_quantity=item["new_quantity"],
                    timestamp_ns=item.get("timestamp_ns", 0),
                )
            case _:
                console.print(f"[yellow]Skipping unknown event: {ev_type}[/]")
                continue

        rec = book.step(ev)
        render_audit_record(rec, console)
        render_book_ladder(book, console=console)
        if pause:
            input("\n[Press Enter to continue...]")


def main() -> None:
    """Main CLI entrypoint."""
    parser = argparse.ArgumentParser(
        description="Limit Order Book (LOB) Simulator and Verification Engine"
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    # Subcommand: demo
    demo_p = subparsers.add_parser(
        "demo", help="Step through worked scenarios (A..H)"
    )
    demo_p.add_argument(
        "--scenario",
        "-s",
        default="A",
        help="Scenario to run: A, B, C, D, E, F, G, H, or ALL (default: A)",
    )
    demo_p.add_argument(
        "--pause",
        "-p",
        action="store_true",
        help="Pause between events for interactive inspection",
    )

    # Subcommand: show-book
    show_p = subparsers.add_parser(
        "show-book", help="Render ladder book for scenario"
    )
    show_p.add_argument(
        "--scenario", "-s", default="A", help="Scenario to inspect (default: A)"
    )

    # Subcommand: explain-last-event
    explain_p = subparsers.add_parser(
        "explain-last-event", help="Explain last audit transition"
    )
    explain_p.add_argument(
        "--scenario", "-s", default="B", help="Scenario to inspect (default: B)"
    )

    # Subcommand: stats
    stats_p = subparsers.add_parser(
        "stats", help="Display market statistics for a scenario"
    )
    stats_p.add_argument(
        "--scenario", "-s", default="A", help="Scenario to inspect (default: A)"
    )

    # Subcommand: self-test
    subparsers.add_parser("self-test", help="Run full pytest verification suite")

    # Subcommand: run
    run_p = subparsers.add_parser("run", help="Run JSON scenario file")
    run_p.add_argument("file", help="Path to scenario JSON file")
    run_p.add_argument(
        "--pause", "-p", action="store_true", help="Pause between events"
    )

    # Subcommand: export-vectors
    exp_p = subparsers.add_parser(
        "export-vectors", help="Export deterministic RTL testbench vectors"
    )
    exp_p.add_argument(
        "--output",
        "-o",
        default="testbench_vectors.json",
        help="Output JSON file path",
    )

    args = parser.parse_args()
    console = Console()

    match args.command:
        case "demo":
            cmd_demo(args.scenario, args.pause, console)
        case "show-book":
            book, _ = run_scenario(args.scenario)
            render_book_ladder(book, console=console)
        case "explain-last-event":
            book, records = run_scenario(args.scenario)
            if records:
                render_audit_record(records[-1], console)
            render_book_ladder(book, console=console)
        case "stats":
            cmd_stats(args.scenario, console)
        case "self-test":
            cmd_self_test(console)
        case "run":
            cmd_run_file(args.file, args.pause, console)
        case "export-vectors":
            export_rtl_vectors(args.output)


if __name__ == "__main__":
    main()
