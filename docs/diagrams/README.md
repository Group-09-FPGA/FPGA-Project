# Historical diagrams

This Vite app and the static figures were made during an earlier design phase.
They are presentation material, not an implementation reference. For current
clocking, protocol behavior, and timing, use the RTL, tests, and the latest
`build_system/post_route_timing.rpt`.

To view the interactive diagrams:

```bash
cd docs/diagrams
pnpm install
pnpm dev
```

The original figure sources are `dg.py` and `fig1_cpu.py` through
`fig4_divider.py`. One-off scripts used to patch intermediate figure versions
were removed; regenerate a figure by running its source script directly.
