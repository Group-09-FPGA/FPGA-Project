# Documentation

The RTL and reproducible tests determine implemented behavior. This directory
also contains reports and slides from earlier project phases; those are
historical and may describe different clocks, resource counts, or latency.

- [Commands](commands.md): tests, firmware, the one full-system build, and board bringup.
- [Hardware validation](HARDWARE_VALIDATION.md): physical test record, still unfilled because no board was available.
- [Audit follow-up](AUDIT_FOLLOWUP.md): remaining evidence and engineering limits.
- [Routed DRC review](DRC_REVIEW.md): rule-by-rule warning assessment.

For current routed timing and DRC, regenerate `build_system/` with
`vivado/scripts/build_system_bitstream.tcl`. Do not use
`CURRENT_IMPLEMENTATION.md` as a contract for the RTL; it is an older snapshot.
