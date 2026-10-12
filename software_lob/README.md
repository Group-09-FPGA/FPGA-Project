# Python Limit Order Book (LOB) Simulator & FPGA Verification Framework

A deterministic, educational, and technically rigorous Python Limit Order Book (LOB) reference model and verification framework.

This project serves as the **gold-standard functional reference model** for an FPGA-accelerated electronic trading system featuring an RV32IM RISC-V soft core, Ethernet/RMII receiver, MoldUDP64 decapsulator, NASDAQ TotalView-ITCH 5.0 parser, asynchronous FIFO clock-domain bridge, BRAM-backed order book, MMIO top-of-book registers, and a real-time VGA ladder display.

---

## 1. Project Architecture

```
lob-simulator/
├── README.md
├── pyproject.toml
├── testbench_vectors.json        # Deterministic golden vectors for RTL testbenches
├── docs/
│   ├── financial_concepts.md     # Primer on orders, book mechanics, BBO, and stats
│   ├── feed_semantics.md         # NASDAQ ITCH 5.0 & MoldUDP64 byte-level specification
│   ├── architecture.md           # Decoupled layer design & dataflow
│   ├── test_plan.md              # Test matrix, invariants, and property-based verification
│   └── fpga_mapping.md           # Hardware-software co-design & MMIO register mapping
├── src/
│   └── lob_sim/
│       ├── __init__.py
│       ├── models.py             # Enums & dataclasses (Order, Side, TOBSnapshot, etc.)
│       ├── price_levels.py       # FIFO order queue & price aggregate tracking
│       ├── events.py             # Normalized events & AuditRecord structure
│       ├── statistics.py         # Spread, midpoint, imbalance, VWAP, multi-level depth
│       ├── order_book.py         # Core LOB engine & invariant auditor
│       ├── reference_model.py    # Independent brute-force model for differential testing
│       ├── feed_decoder.py       # NASDAQ ITCH 5.0 binary parser & encoder
│       ├── moldudp64.py          # MoldUDP64 packet parser & serializer
│       ├── recovery.py           # Transport receiver & sequence gap recovery state machine
│       ├── scenarios.py          # Worked scenarios A through H
│       ├── visualization.py      # Rich ANSI terminal ladder book & audit formatter
│       └── cli.py                # Interactive CLI (demo, run, show-book, stats, self-test)
├── tests/
│   ├── unit/                     # Unit tests for book, levels, stats, decoder, transport
│   ├── scenarios/                # Automated verification of Scenarios A through H
│   ├── property/                 # Hypothesis invariant fuzzing & differential testing
│   └── regression/               # Boundary conditions, 48-bit timestamps, locked markets
└── examples/
    ├── scenario_a.json           # Add orders & TOB updates
    ├── scenario_b.json           # Partial and full execution
    ├── scenario_c.json           # Cancellation and deletion
    ├── scenario_d.json           # Dynamic TOB shifts & side depletion
    ├── scenario_e.json           # Price-time FIFO priority queueing
    ├── scenario_f.json           # Order replace & queue demotion
    ├── scenario_g.json           # Trade reporting, non-displayed trades, VWAP
    └── scenario_h.json           # Invalid input rejection & corruption resistance
```

---

## 2. Key Design Principles

1. **Passive Market-Data Consumer Role**:
   - The primary simulator models a consumer reconstructing the order book from broadcast market-data events. It does not match trades or invent counterparty orders.
2. **Strict Integer Price Units**:
   - All financial prices are stored as unsigned 32-bit integers (`uint32`) in fixed-point format (4 implied decimal places, e.g. \$100.2500 is `1002500`). Floating-point numbers are prohibited in core book state.
3. **Exact Protocol Compliance**:
   - Complies with official NASDAQ TotalView-ITCH 5.0 and MoldUDP64 specifications (big-endian encoding, 48-bit nanosecond timestamps).
4. **Hardware Correspondence**:
   - Software structures map directly to FPGA Block RAMs, slot tables, occupancy hierarchies, and MMIO registers.

---

## 3. Installation & Quickstart

### Prerequisites
- Python 3.12+
- `uv` package manager (recommended) or `pip`

### Setup with `uv`
```bash
# Clone the repository and navigate into it
cd intelligent-planck

# Create virtual environment and install dependencies
uv venv --python 3.12
source .venv/bin/activate
uv pip install -e ".[dev]"
```

---

## 4. Interactive CLI Usage

The simulator includes a rich educational CLI for inspecting order book dynamics:

### 1. Interactive Demo Walkthrough
Step through pre-built scenarios with visual ladder rendering and full audit traces:
```bash
# Run Scenario A (Add orders & TOB shifts)
python -m lob_sim.cli demo --scenario A

# Run Scenario B with step-by-step pause
python -m lob_sim.cli demo --scenario B --pause

# Run all scenarios A through H
python -m lob_sim.cli demo --scenario ALL
```

### 2. View Terminal Ladder Book
Display a two-sided order book ladder with BBO highlighted:
```bash
python -m lob_sim.cli show-book --scenario A
```

### 3. Comprehensive Market Statistics
Calculate and inspect BBO, spread (price and ticks), midpoint, TOB imbalance, depth-weighted imbalance, volume at price, and VWAP:
```bash
python -m lob_sim.cli stats --scenario A
```

### 4. Execute Custom JSON Scenarios
Run custom event sequences from file:
```bash
python -m lob_sim.cli run examples/scenario_b.json
```

### 5. Run Verification Self-Test
Run the full test suite directly from the CLI:
```bash
python -m lob_sim.cli self-test
```

### 6. Export Golden FPGA Test Vectors
Generate deterministic JSON vectors for RTL testbench verification:
```bash
python -m lob_sim.cli export-vectors --output testbench_vectors.json
```

---

## 5. Verification & Test Suite

The verification suite features 42 automated tests across unit, scenario, regression, and Hypothesis property-based testing:

```bash
# Run complete test suite with verbose output
uv run pytest tests/ -v
```

### Verification Matrix:
- **Unit Tests (`tests/unit/`)**:
  - `test_order_book.py`: Event handling, BBO tracking, defensive rejection.
  - `test_price_levels.py`: FIFO queue operations, aggregate quantity conservation.
  - `test_statistics.py`: Spread, midpoint, imbalance, VWAP, multi-level depth.
  - `test_feed_decoder.py`: ITCH 5.0 binary encoding and decoding (all message types).
  - `test_moldudp64.py`: Packet framing, heartbeats, end-of-session handling.
  - `test_recovery.py`: Sequence gap detection, packet buffering, backfill recovery.
- **Scenario Tests (`tests/scenarios/`)**:
  - Automated tests verifying exact expected outputs for Scenarios A through H.
- **Property-Based Tests (`tests/property/`)**:
  - `test_invariants.py`: Fuzz testing checking 8 structural and mathematical invariants after every event.
  - `test_differential.py`: Differential fuzzing against the naive list reference model.
- **Regression Tests (`tests/regression/`)**:
  - Boundary conditions, 48-bit timestamp overflow, locked and crossed market detection.

---

## 6. Financial Concepts Glossary

| Term | Definition |
| :--- | :--- |
| **Limit Order** | An order to buy or sell a specified quantity at a specified limit price or better. |
| **Bid (Buy)** | Displayed buying interest resting in the book, sorted in descending price order. |
| **Ask / Offer (Sell)** | Displayed selling interest resting in the book, sorted in ascending price order. |
| **Price Level** | A distinct limit price tier aggregating all resting orders at that price into a total quantity and order count. |
| **Price-Time Priority (FIFO)**| Priority rule where orders at better prices execute first; orders at the same price execute in order of arrival. |
| **Best Bid & Offer (BBO)** | Highest resting buy price and lowest resting sell price currently displayed in the book. |
| **Bid–Ask Spread** | Difference between the best ask and best bid: $\text{Spread} = P_{\text{best ask}} - P_{\text{best bid}}$. |
| **Midpoint** | Halfway price between best bid and best ask: $\text{Midpoint} = (P_{\text{best ask}} + P_{\text{best bid}}) / 2$. |
| **Top-of-Book Imbalance** | Ratio measuring directional supply/demand skew: $(Q_{\text{bid}} - Q_{\text{ask}}) / (Q_{\text{bid}} + Q_{\text{ask}})$. |
| **VWAP** | Volume-Weighted Average Price across all trade reports: $\sum (P_i \times Q_i) / \sum Q_i$. |
| **Locked Market** | State where best bid equals best ask ($\text{Spread} == 0$). |
| **Crossed Market** | Anomalous or transient state where best bid exceeds best ask ($\text{Spread} < 0$). |

---

## 7. FPGA Hardware Correspondence

| Python Software Reference | FPGA Hardware Equivalent | Notes |
| :--- | :--- | :--- |
| `dict[uint64, Order]` | Hash Table / CAM in BRAM | Fast 64-bit Order ID lookup. |
| `Order` dataclass | Slot Table / Order RAM | Packed bit-fields for price, quantity, pointers. |
| `PriceLevel` FIFO | Price-Level Dual-Port BRAM | Stores aggregate quantity, count, head/tail pointers. |
| `SortedDict` BBO Search | Occupancy Bitmap / Priority Tree | Single-cycle best bid / ask resolution. |
| `step()` Event Logic | LOB Sequencer State Machine | Pipelined read-modify-write state transitions. |
| Input Event Queue | Asynchronous Dual-Clock FIFO | Bridges network clock domain to LOB clock domain. |
| `TOBSnapshot` | MMIO Status & Snapshot Registers | Memory-mapped registers accessible by RV32IM CPU. |
| `testbench_vectors.json` | Testbench Stimulus Vectors | Verified against RTL testbenches in simulation. |

For detailed hardware architectures and MMIO register offsets, consult [`docs/fpga_mapping.md`](file:///home/ronit/Documents/antigravity/intelligent-planck/docs/fpga_mapping.md).
