export default function Slide6_ModuleTable() {
  const modules = [
    { mod: 'cpu_core', purpose: '3-stage RV32IM processor pipeline core (IF, EX, WB, bus arbiter)', file: 'rtl/cpu/core/cpu_core.v', type: 'Hardware (Verilog)', status: 'Existing + Modified' },
    { mod: 'decoder', purpose: 'Instruction decoder for RV32I base instructions and M-extension opcode', file: 'rtl/cpu/core/decoder.v', type: 'Hardware (Verilog)', status: 'Existing' },
    { mod: 'alu', purpose: '32-bit combinational arithmetic & logic unit (ADD, SUB, shifts, logic)', file: 'rtl/cpu/core/alu.v', type: 'Hardware (Verilog)', status: 'Existing' },
    { mod: 'branch_unit', purpose: 'Branch condition evaluator (BEQ, BNE, BLT, BGE, BLTU, BGEU)', file: 'rtl/cpu/core/branch_unit.v', type: 'Hardware (Verilog)', status: 'Existing' },
    { mod: 'rv32m_unit', purpose: '★ Multi-cycle 3-stage pipelined multiplier (3cy) and 32-iter restoring divider (33cy)', file: 'rtl/cpu/core/rv32m_unit.v', type: 'Hardware (Verilog)', status: '★ NEW Hardware' },
    { mod: 'reg_file', purpose: '32 × 32-bit dual-read sync-write general-purpose register file', file: 'rtl/cpu/core/reg_file.v', type: 'Hardware (Verilog)', status: 'Existing' },
    { mod: 'forwarding_unit', purpose: 'Hazard mitigation unit; bypasses WB stage results directly to EX operands', file: 'rtl/cpu/core/forwarding_unit.v', type: 'Hardware (Verilog)', status: 'Existing' },
    { mod: 'hazard_unit', purpose: 'Pipeline stall and bubble generator; inserts 2-cycle penalty on taken branches', file: 'rtl/cpu/core/hazard_unit.v', type: 'Hardware (Verilog)', status: 'Existing' },
    { mod: 'memory (IMEM/DMEM)', purpose: 'Instruction & Data Block RAMs (4 KB each) with synchronous byte-write strobe', file: 'rtl/cpu/core/memory.v', type: 'Hardware (Verilog)', status: 'Existing' },
    { mod: 'sys_bus_interconnect', purpose: '32-bit pipelined memory bus arbiter & slave address decoder', file: 'rtl/cpu/core/sys_bus_interconnect.v', type: 'Hardware (Verilog)', status: 'Existing' },
    { mod: 'lob_mmio_slave', purpose: 'Memory-mapped slave at 0x4000_0000; provides CPU access to live BBO shadow regs', file: 'rtl/bus/lob_mmio_slave.sv', type: 'Hardware (SystemVerilog)', status: '★ NEW Hardware' },
    { mod: 'async_event_fifo', purpose: '512 × 128-bit dual-clock asynchronous FIFO with Gray-coded read/write pointers', file: 'rtl/common/async_event_fifo.sv', type: 'Hardware (SystemVerilog)', status: '★ NEW Hardware' },
    { mod: 'lob_core', purpose: 'Limit Order Book Op Sequencer FSM; enforces deterministic 10-cycle Add schedule', file: 'rtl/lob/lob_core.sv', type: 'Hardware (SystemVerilog)', status: '★ NEW Hardware' },
    { mod: 'lob_event_decoder', purpose: 'Unpacks 128-bit Canonical Event into Opcode, Order_ID, Price, and Shares', file: 'rtl/lob/lob_event_decoder.sv', type: 'Hardware (SystemVerilog)', status: '★ NEW Hardware' },
    { mod: 'lob_hash_table', purpose: '2048-set 4-way associative hash table indexed via CRC32-C (8,192 entries)', file: 'rtl/lob/lob_hash_table.sv', type: 'Hardware (SystemVerilog)', status: '★ NEW Hardware' },
    { mod: 'lob_slot_table', purpose: '4096 × 129-bit order record memory (Valid, Side, Order_ID, Price, Qty)', file: 'rtl/lob/lob_slot_table.sv', type: 'Hardware (SystemVerilog)', status: '★ NEW Hardware' },
    { mod: 'lob_free_list', purpose: '4096-depth circular FIFO tracking unallocated slot indices', file: 'rtl/lob/lob_free_list.sv', type: 'Hardware (SystemVerilog)', status: '★ NEW Hardware' },
    { mod: 'lob_price_ram', purpose: '65,536 × 32-bit true dual-port RAM storing cumulative share quantities per tick', file: 'rtl/lob/lob_price_ram.sv', type: 'Hardware (SystemVerilog)', status: '★ NEW Hardware' },
    { mod: 'lob_occupancy', purpose: '3-level hierarchical occupancy mask (Reg, LUTRAM, BRAM) for zero-count detection', file: 'rtl/lob/lob_occupancy.sv', type: 'Hardware (SystemVerilog)', status: '★ NEW Hardware' },
    { mod: 'lob_bbo', purpose: 'Priority encoder engine scanning occupancy mask to calculate Best Bid & Best Ask', file: 'rtl/lob/lob_bbo.sv', type: 'Hardware (SystemVerilog)', status: '★ NEW Hardware' },
    { mod: 'rmii_rx', purpose: '100 Mbps RMII physical layer receiver; 2-bit di-bit to byte converter & CRC32 FCS', file: 'rtl/ethernet/rmii_rx.sv', type: 'Hardware (SystemVerilog)', status: '★ NEW Hardware' },
    { mod: 'net_parser', purpose: 'IPv4 / UDP header parser; validates EtherType and applies UDP port filter', file: 'rtl/network/net_parser.sv', type: 'Hardware (SystemVerilog)', status: '★ NEW Hardware' },
    { mod: 'moldudp64_decoder', purpose: 'MoldUDP64 packet sequence tracker; detects missing/duplicate packets and gaps', file: 'rtl/network/moldudp64_decoder.sv', type: 'Hardware (SystemVerilog)', status: '★ NEW Hardware' },
    { mod: 'itch_decoder', purpose: 'NASDAQ ITCH 5.0 feed parser; decodes A, F, E, C, X, D, U into 128-bit events', file: 'rtl/itch/itch_decoder.sv', type: 'Hardware (SystemVerilog)', status: '★ NEW Hardware' },
    { mod: 'clk_rst_mgr', purpose: 'Xilinx 7-series MMCM generating 100 MHz, 50 MHz, and 25.175 MHz synchronized clocks', file: 'rtl/clocking/clk_rst_mgr.sv', type: 'Hardware (SystemVerilog)', status: '★ NEW Hardware' },
    { mod: 'GLIMPSE Client (SW)', purpose: 'TCP recovery software running bare-metal on RV32IM to download book snapshot', file: 'software/recovery/glimpse.c', type: 'Software (C / Baremetal)', status: 'Software Driver' },
    { mod: 'Order Book Driver (SW)', purpose: 'C library reading BBO shadow registers over MMIO and formatting telemetry', file: 'software/drivers/lob_mmio.h', type: 'Software (C / Baremetal)', status: 'Software Driver' },
  ]

  const resources = [
    { res: 'Block RAM (RAMB36E1)', avail: '135', used: '120 (CPU: 4, LOB: 107, VGA: 9)', pct: '88.9%', status: 'Within Budget (Critical Path)' },
    { res: 'DSP48E1 Slices', avail: '240', used: '12 (MUL Unit Array: 4, Adders: 8)', pct: '5.0%', status: 'Abundant Headroom' },
    { res: 'Logic LUTs', avail: '63,400', used: '~9,200 (CPU: 2,688, LOB: 4,500, ETH: 2,000)', pct: '14.5%', status: 'Abundant Headroom' },
    { res: 'Flip-Flops (Registers)', avail: '126,800', used: '~12,400 (CPU: 3,100, LOB: 6,800, Net: 2,500)', pct: '9.8%', status: 'Abundant Headroom' },
  ]

  return (
    <div style={{ position: 'relative', width: 1760, height: 860, margin: '20px auto 0', overflowY: 'auto', paddingRight: 10 }}>
      <div style={{ display: 'grid', gridTemplateColumns: '1.4fr 1fr', gap: 32 }}>
        {/* ── Left Column: Module Summary Table ── */}
        <div>
          <div style={{ font: '700 15px var(--mono)', color: 'var(--navy)', letterSpacing: '.08em', textTransform: 'uppercase', marginBottom: 8 }}>
            Module Summary Table (All 27 Project Modules)
          </div>
          <div style={{ background: '#ffffff', border: '1.5px solid var(--line)', borderRadius: 4, overflow: 'hidden' }}>
            <table style={{ width: '100%', borderCollapse: 'collapse', font: '12px var(--mono)' }}>
              <thead>
                <tr style={{ background: '#f5f5f3', borderBottom: '1.5px solid var(--line)', textAlign: 'left', color: 'var(--ink-2)' }}>
                  <th style={{ padding: '8px 10px' }}>Module</th>
                  <th style={{ padding: '8px 10px' }}>Type / Language</th>
                  <th style={{ padding: '8px 10px' }}>Source File</th>
                  <th style={{ padding: '8px 10px' }}>Purpose &amp; Hardware Contribution</th>
                </tr>
              </thead>
              <tbody>
                {modules.map((m, i) => (
                  <tr key={m.mod} style={{ borderBottom: '1px solid #e8e8e4', background: i % 2 === 0 ? '#ffffff' : '#fafaf8' }}>
                    <td style={{ padding: '6px 10px', fontWeight: 700, color: m.status.includes('NEW') ? 'var(--navy)' : 'var(--ink)' }}>
                      {m.mod}
                    </td>
                    <td style={{ padding: '6px 10px' }}>
                      <span
                        style={{
                          padding: '2px 6px',
                          borderRadius: 2,
                          fontSize: 10,
                          fontWeight: 600,
                          background: m.type.includes('Hardware') ? '#e4e6f8' : '#e0e0dc',
                          color: m.type.includes('Hardware') ? 'var(--navy)' : 'var(--ink)',
                        }}
                      >
                        {m.type}
                      </span>
                    </td>
                    <td style={{ padding: '6px 10px', color: 'var(--ink-3)', fontSize: 11 }}>{m.file}</td>
                    <td style={{ padding: '6px 10px', color: 'var(--ink-2)', fontSize: 11 }}>{m.purpose}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>

        {/* ── Right Column: FPGA Resource Estimates & Verification ── */}
        <div>
          {/* Resource Estimates */}
          <div style={{ font: '700 15px var(--mono)', color: 'var(--navy)', letterSpacing: '.08em', textTransform: 'uppercase', marginBottom: 8 }}>
            Hardware Resource Estimates (Artix-7 XC7A100T)
          </div>
          <div style={{ background: '#ffffff', border: '1.5px solid var(--line)', borderRadius: 4, overflow: 'hidden', marginBottom: 24 }}>
            <table style={{ width: '100%', borderCollapse: 'collapse', font: '13px var(--mono)' }}>
              <thead>
                <tr style={{ background: '#f5f5f3', borderBottom: '1.5px solid var(--line)', textAlign: 'left', color: 'var(--ink-2)' }}>
                  <th style={{ padding: '8px 12px' }}>Resource</th>
                  <th style={{ padding: '8px 12px' }}>Max Available</th>
                  <th style={{ padding: '8px 12px' }}>Estimated Usage</th>
                  <th style={{ padding: '8px 12px' }}>% Utilization</th>
                </tr>
              </thead>
              <tbody>
                {resources.map((r) => (
                  <tr key={r.res} style={{ borderBottom: '1px solid #e8e8e4' }}>
                    <td style={{ padding: '10px 12px', fontWeight: 600, color: 'var(--ink)' }}>{r.res}</td>
                    <td style={{ padding: '10px 12px', color: 'var(--ink-3)' }}>{r.avail}</td>
                    <td style={{ padding: '10px 12px', color: 'var(--navy)', fontWeight: 600 }}>{r.used}</td>
                    <td style={{ padding: '10px 12px', fontWeight: 700, color: r.pct.includes('88') ? 'var(--warn)' : 'var(--ok)' }}>
                      {r.pct}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          {/* Verification Strategy */}
          <div style={{ font: '700 15px var(--mono)', color: 'var(--navy)', letterSpacing: '.08em', textTransform: 'uppercase', marginBottom: 8 }}>
            Verification Plans (Edge Cases &amp; Validation)
          </div>
          <div style={{ background: '#ffffff', border: '1.5px solid var(--line)', padding: '16px 20px', borderRadius: 4, marginBottom: 24 }}>
            <ul style={{ margin: 0, paddingLeft: 20, display: 'grid', gap: 8, font: '14px/1.4 var(--font)', color: 'var(--ink-2)' }}>
              <li>
                <b>RV32M Arithmetic &amp; Hazard Unit:</b> Verified with directed testbenches covering signed/unsigned extremes (INT_MIN / -1 overflow, divide-by-zero 0xFFFF_FFFF), RAW operand forwarding, and taken branch bubble assertion in Vivado XSim.
              </li>
              <li>
                <b>Order Book Hash Table &amp; Capacity Invariants:</b> Validated via randomized order streams and directed hash collision testbenches to verify 4-way associative placement and 16-entry CAM stash overflow.
              </li>
              <li>
                <b>End-to-End System Integration:</b> PCAP replay of NASDAQ ITCH 5.0 real trade traces against a bit-exact Python golden model, verifying BBO shadow register values for 1,000,000 continuous market events.
              </li>
            </ul>
          </div>

          {/* Risks & Mitigation */}
          <div style={{ font: '700 15px var(--mono)', color: 'var(--navy)', letterSpacing: '.08em', textTransform: 'uppercase', marginBottom: 8 }}>
            Key Technical Risks &amp; Mitigations
          </div>
          <div style={{ background: '#ffffff', border: '1.5px solid var(--warn)', padding: '16px 20px', borderRadius: 4 }}>
            <ul style={{ margin: 0, paddingLeft: 20, display: 'grid', gap: 6, font: '13.5px/1.4 var(--font)', color: 'var(--ink-2)' }}>
              <li><b>BRAM Congestion (89% utilization):</b> If place-and-route fails, Price Level RAM depth will be halved from 65,536 to 32,768 entries, immediately recovering 32 BRAMs (24%).</li>
              <li><b>Multi-Cycle Pipeline Stalls:</b> Formal assertions in testbench verify that IF skid buffer retains fetched words across all 3-cycle MUL and 33-cycle DIV stall periods.</li>
              <li><b>CDC Metastability on Network Input:</b> Dual-clock FIFO uses Gray-coded pointers double-flopped into respective domains with Vivado <code>set_max_delay -datapath_only</code> constraints.</li>
            </ul>
          </div>
        </div>
      </div>
    </div>
  )
}
