# Routed DRC review

Vivado 2026.1 reports **0 errors** for the routed Nexys A7-100T design. Its
default report lists 105 warnings. `CHECK-3` says the display limit of 20 was
reached for both `REQP-1839` and `REQP-1840`, so 105 is a report count, not a
claim that every affected pin was enumerated. See
`build_system/post_route_drc.rpt` for the exact routed netlist and pin names.

| Rule | Listed | Assessment |
| --- | ---: | --- |
| `DPIP-1`, `DPOP-1`, `DPOP-2` | 29 | DSP input/output pipeline suggestions for CPU RV32M and BBO multiplies. The current latency is part of the RTL interface; adding registers changes transaction timing. The routed setup path meets timing, so this is a power/performance opportunity, not a functional failure. |
| `DPOR-1` | 34 | CPU RV32M product registers use asynchronous reset, which prevents Vivado from absorbing them into DSP pipeline registers. The reset behavior is intentional. Changing it only to reduce this advisory would alter reset semantics. |
| `REQP-1839` | 20 shown | The reported RAMB36 is the **instruction memory read port**. Its contents are loaded from `imem.hex`; the RTL has no write port for instruction fetch. Asynchronous reset of address-source registers can change an ignored read value during reset, but cannot corrupt this memory. |
| `REQP-1840` | 20 shown | The reported RAMB18 controls belong to reset-reinitialized hash storage and the UDP packet buffer. The hash table is cleared by its initialization sweep before the book is marked valid; the parser gates packet-buffer writes with `rst_n` and discards an in-flight packet on reset. A read or partial write during reset is not accepted as a valid event. |
| `CHECK-3` | 2 | The two RAM rules hit Vivado's report limit; this is a reporting warning. |

We tested synchronous-reset variants of the register banks named by the first
RAM warnings. They passed simulation but Vivado then reported other
asynchronous reset sources feeding the same RAM controls; the broad variant
also reduced routed setup margin. Those experimental RTL changes were
reverted. The reset manager intentionally asserts reset asynchronously and
releases it synchronously, and the design's initialization protocols discard
state during reset. The board reset/recovery sequence was checked as recorded
in `HARDWARE_VALIDATION.md`.

This review does not waive or suppress the warnings. Any future change to
memory write enables, initialization, or reset sequencing must repeat the DRC
review and reset regressions.

Vivado's methodology report was also checked. It flags the same DSP reset
optimization opportunities, LUT RAM mapping of byte-write data memory, and
unregistered RAM outputs. `TIMING-28` identified two RMII input-delay
constraints that referred to an auto-derived clock by name; those constraints
now identify the MMCM output pin. `LUTAR-1` identifies the AND of the active-low
reset button and MMCM lock driving reset synchronizers and the PHY reset
counter. The AND is intentional: loss of either signal must assert reset, and
extra assertion during their transition delays startup rather than accepting
traffic. The implementation has no methodology errors. Its control-set and
wide-multiplier recommendations are resource/timing advice, not timing
violations.
