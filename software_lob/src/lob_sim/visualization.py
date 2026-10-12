"""Terminal ladder book visualization and market dashboard using Rich."""

from __future__ import annotations

from rich.align import Align
from rich.console import Console
from rich.layout import Layout
from rich.panel import Panel
from rich.table import Table
from rich.text import Text

from lob_sim.events import AuditRecord
from lob_sim.order_book import OrderBook


def render_book_ladder(
    book: OrderBook, depth: int = 10, console: Console | None = None
) -> None:
    """Print an ANSI terminal ladder displaying bids and asks side-by-side with TOB highlighted."""
    if console is None:
        console = Console()

    tob = book.get_tob()
    bids = book.get_bids_depth(depth)
    asks = book.get_asks_depth(depth)
    stats = book.get_statistics()

    # Create ladder table
    table = Table(
        title=f"LIMIT ORDER BOOK: {book.symbol} (Status: {'VALID' if book.is_valid else 'INVALID/GAP'})",
        title_style="bold cyan",
        header_style="bold magenta",
        border_style="bright_blue",
    )

    table.add_column("Orders (B)", justify="right", style="cyan", width=10)
    table.add_column("Bid Size", justify="right", style="bold green", width=12)
    table.add_column("Bid Price (₹)", justify="right", style="green", width=14)
    table.add_column("Ask Price (₹)", justify="left", style="red", width=14)
    table.add_column("Ask Size", justify="left", style="bold red", width=12)
    table.add_column("Orders (A)", justify="left", style="cyan", width=10)

    max_rows = max(len(bids), len(asks), 1)

    for i in range(max_rows):
        # Bid side
        if i < len(bids):
            b_lvl = bids[i]
            is_bbo_bid = (b_lvl.price == tob.best_bid_price)
            b_orders = str(b_lvl.order_count)
            b_size = f"{b_lvl.total_quantity:,}"
            b_price = f"{b_lvl.price / 10000:.4f}"
            if is_bbo_bid:
                b_price = f"★ {b_price}"
                b_style = "bold green reverse"
            else:
                b_style = "green"
        else:
            b_orders, b_size, b_price, b_style = "-", "-", "-", "dim"

        # Ask side
        if i < len(asks):
            a_lvl = asks[i]
            is_bbo_ask = (a_lvl.price == tob.best_ask_price)
            a_orders = str(a_lvl.order_count)
            a_size = f"{a_lvl.total_quantity:,}"
            a_price = f"{a_lvl.price / 10000:.4f}"
            if is_bbo_ask:
                a_price = f"{a_price} ★"
                a_style = "bold red reverse"
            else:
                a_style = "red"
        else:
            a_orders, a_size, a_price, a_style = "-", "-", "-", "dim"

        table.add_row(
            Text(b_orders, style=b_style),
            Text(b_size, style=b_style),
            Text(b_price, style=b_style),
            Text(a_price, style=a_style),
            Text(a_size, style=a_style),
            Text(a_orders, style=a_style),
        )

    console.print(table)

    # Print TOB and statistics summary bar
    spread_str = (
        f"₹{tob.spread / 10000:.4f} ({stats.spread_ticks:.1f} ticks)"
        if tob.spread is not None and stats.spread_ticks is not None
        else "N/A"
    )
    mid_str = (
        f"₹{tob.midpoint / 10000:.4f}" if tob.midpoint is not None else "N/A"
    )
    vwap_str = (
        f"₹{stats.vwap / 10000:.4f}" if stats.vwap is not None else "N/A"
    )

    stats_text = (
        f"[bold]Spread:[/] {spread_str} | "
        f"[bold]Midpoint:[/] {mid_str} | "
        f"[bold]TOB Imbalance:[/] {stats.tob_imbalance:+.2f} | "
        f"[bold]VWAP:[/] {vwap_str} | "
        f"[bold]Traded Vol:[/] {stats.cumulative_volume:,} | "
        f"[bold]Trades:[/] {stats.trade_count}"
    )
    console.print(Panel(Align.center(stats_text), style="bright_yellow"))


def render_audit_record(record: AuditRecord, console: Console | None = None) -> None:
    """Print an educational, structured explanation of an audit record."""
    if console is None:
        console = Console()

    status_style = "bold green" if record.success else "bold red"
    status_label = "SUCCESS" if record.success else f"REJECTED ({record.error_message})"

    title = f"EVENT {record.event_number}: {type(record.event).__name__} — [{status_style}]{status_label}[/]"
    content = []

    content.append(f"[bold cyan]Description:[/] {record.explanation}\n")

    if record.order_before or record.order_after:
        content.append("[bold]Order State Transition:[/]")
        if record.order_before:
            content.append(
                f"  Before: Order {record.order_before.order_id} ({record.order_before.side.value}) "
                f"rem={record.order_before.remaining_qty} @ ₹{record.order_before.price / 10000:.4f}"
            )
        else:
            content.append("  Before: (None)")

        if record.order_after:
            content.append(
                f"  After:  Order {record.order_after.order_id} ({record.order_after.side.value}) "
                f"rem={record.order_after.remaining_qty} @ ₹{record.order_after.price / 10000:.4f}"
            )
        else:
            content.append("  After:  (Deleted / Filled / None)")
        content.append("")

    content.append("[bold]Top of Book Transition:[/]")
    tb = record.tob_before
    ta = record.tob_after

    def fmt_tob(t):
        bid = f"₹{t.best_bid_price / 10000:.4f} × {t.best_bid_qty}" if t.best_bid_price else "Empty"
        ask = f"₹{t.best_ask_price / 10000:.4f} × {t.best_ask_qty}" if t.best_ask_price else "Empty"
        spr = f"₹{t.spread / 10000:.4f}" if t.spread is not None else "N/A"
        return f"Bid: {bid} | Ask: {ask} | Spread: {spr}"

    content.append(f"  Before: {fmt_tob(tb)}")
    content.append(f"  After:  {fmt_tob(ta)}")

    console.print(Panel("\n".join(content), title=title, border_style="blue"))
