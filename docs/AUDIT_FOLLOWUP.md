# Audit follow-up

This records the remaining physical validation and the evidence from the
October 2026 source audit. It is based on RTL and tool results, not earlier
architecture descriptions.

The 2026-10-24 board run validated Ethernet ingest, UART, visible book changes,
several fail-stop paths, and recovery by both JTAG reprogramming and the
CPU RESETN pushbutton followed by replay. The remaining physical checks are
VGA output, deliberately bad Ethernet FCS, and exact quantity and internal diagnostic values.
The tested bitstream and observations are identified in `HARDWARE_VALIDATION.md`.

The implementation evidence is complete for the available tools:

- The Explore route produced +0.673 ns setup and +0.025 ns hold slack. The
  final Default route, with corrected clock references, produced +0.817 ns
  setup and +0.030 ns hold slack. Both had zero failing endpoints. These two
  runs do not establish operation at every process, voltage, and temperature
  corner.
- The final routed DRC has zero errors. Its warnings and the methodology
  findings are assessed in `DRC_REVIEW.md`; repeat that review if reset,
  memory write, or timing constraints change.
- Older architecture pages and the presentation are labelled historical.
  Their earlier 100 MHz and reciprocal-conversion claims do not describe the
  current RTL.

The packet buffer now infers a block RAM and the asynchronous event FIFO
infers distributed RAM in Vivado synthesis. Their added maximum-payload and
wrap/backpressure regressions pass. Generated waveforms, binaries, simulator
logs, one-off diagram repair scripts, and obsolete build scripts have been
removed from source control. The previously modified `pipeline.vcd` was backed
up at `/home/ronit/.local/share/fpga-lob/audit-2026-10-24/pipeline.vcd`.

The Python reference model continues after a rejected event, while RTL with
fail-stop enabled invalidates the book. The golden comparison covers 31 accepted
events and separately verifies the model's rejected duplicate order as an RTL
fail-stop. Any broader software/RTL comparison must account for that policy
difference explicitly.
