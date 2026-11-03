# Team study guide: five owners, one system

The project is split into five parts so that each person can own a complete,
explainable story. Every folder is named with its **difficulty**:

| Folder | Owner theme | Difficulty | Approx. lines |
| --- | --- | --- | --- |
| [p1-network-and-clocks-medium](p1-network-and-clocks-medium/README.md) | Ethernet in, clocks, clock crossings | Medium | ~1,800 |
| [p2-orderbook-storage-medium-hard](p2-orderbook-storage-medium-hard/README.md) | The order book's memories and best price | Medium-hard | ~1,450 |
| [p3-event-control-hardest](p3-event-control-hardest/README.md) | The sequencer, event legality, keyboard orders, source merging | Hardest | ~1,900 |
| [p4-cpu-and-system-easy](p4-cpu-and-system-easy/README.md) | RISC-V supervisor, bus, registers, LEDs, top-level wiring | Easy to explain | ~2,100 |
| [p5-display-and-uart-medium](p5-display-and-uart-medium/README.md) | VGA display and UART | Medium | ~1,900 |

**Assignment advice:** give person 3 to your strongest hardware person, and
person 4 to whoever is least comfortable, because the CPU is standard RISC-V
material from your course.

## How each folder is organised

Every person's folder has the same shape:

1. `README.md`: role card: 30-second pitch, module list, tests to run, reading order.
2. `01-the-system-from-my-seat.md`: **the whole system as seen from your
   module's position**: everything that comes in, everything that goes out,
   and where your output ends up (including VGA, UART, LEDs). This is the part
   that makes sure, for example, that the Ethernet owner knows an order ends up
   on the monitor.
3. `02-...` onward: your own modules **in depth**, block by block, with the
   code explained, timing, worked examples and edge cases.
4. The last file: **viva questions and model answers**, including "what if..."
   questions.

## Everyone reads this first

- [00-system-in-10-minutes.md](00-system-in-10-minutes.md): the whole design in
  plain language, the interface contracts between the five parts, and the shared
  vocabulary.
- [../study/00-verilog-refresher.md](../study/00-verilog-refresher.md): the
  Verilog ideas the code uses.

## Where this guide sits relative to the older docs

The older [../study](../study/README.md) is a single-reader tour of everything.
This team guide goes deeper on each owner's modules and adds the
"system from my seat" context. Use `study` for breadth, your own folder for depth.

## Tests: how each person demos one live

All tests run from the repository root. The whole list lives in `sim/run_ci_tests.sh`; to run a single one, copy its
`iverilog ... && vvp ...` pair, for example:

```bash
iverilog -g2001 -s tb_uart_tx -o /tmp/t.vvp rtl/telemetry/uart_tx.v sim/unit/tb_uart_tx.v && vvp /tmp/t.vvp
```

Each owner's README lists their testbenches. Run the whole suite with `./sim/run_ci_tests.sh`.
