#!/usr/bin/env python3
"""Stage accepted Python-model vectors for the LOB RTL comparison test."""

import json
import sys
from pathlib import Path


def main(build_dir: Path) -> None:
    source = Path(__file__).with_name("golden_vectors.json")
    vectors = json.loads(source.read_text())
    # The RTL uses fail-stop on invalid orders; the software model records a
    # rejection and keeps processing. Compare the shared accepted-event path.
    accepted = [entry for entry in vectors if entry["expected_success"]]
    rejected = [entry for entry in vectors if not entry["expected_success"]]
    if len(accepted) != 31:
        raise ValueError(f"Expected 31 accepted reference vectors, found {len(accepted)}")
    if len(rejected) != 1 or rejected[0]["step_index"] != 5:
        raise ValueError("Expected the duplicate-order reference at step 5")

    events = []
    expected = []
    for entry in accepted:
        events.append(entry["raw_hex"])
        fields = (
            (entry["expected_book_valid"], 1),
            (entry["expected_active_orders"], 12),
            (entry["expected_best_bid_price"], 32),
            (entry["expected_best_bid_qty"], 32),
            (entry["expected_best_ask_price"], 32),
            (entry["expected_best_ask_qty"], 32),
        )
        word = 0
        for value, width in fields:
            value = int(value)
            if value < 0 or value >= 1 << width:
                raise ValueError(f"Out of range expected field in step {entry['step_index']}")
            word = (word << width) | value
        expected.append(f"{word:036x}")

    build_dir.mkdir(parents=True, exist_ok=True)
    (build_dir / "golden_events.hex").write_text("\n".join(events) + "\n")
    (build_dir / "golden_expected.hex").write_text("\n".join(expected) + "\n")
    (build_dir / "golden_rejected.hex").write_text(rejected[0]["raw_hex"] + "\n")


if __name__ == "__main__":
    main(Path(sys.argv[1]))
