# FPGA LOB presentation

This Vite/React deck records an earlier design phase. Some slides and the
exported PowerPoint retain projected 100 MHz timing and reciprocal price
conversion; these are historical claims, not the implemented RTL. Check
`rtl/clocking/clk_rst_mgr.v`, `rtl/itch/itch_decoder.v`, and a fresh Vivado
post-route report before using the deck to describe current hardware.

Run `pnpm install` and `pnpm dev` to view the deck. Run `pnpm build` to check
the TypeScript and web build.
