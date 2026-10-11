import { Frame } from '../components/Frame'
import { Nut } from '../components/Art'
import { delay } from '../components/util'

const members = [
  {
    m: 'Ronit',
    initials: 'R',
    role: 'Hardware System Bus Architect',
    tag: 'MMIO Arbiter · Bus Interconnect · VGA',
    rtl: 'sys_bus_interconnect.v · MMIO Address Decoder · vga_core.v · wait-state FSM',
    desc: 'Integrating the LOB Accelerator and MMIO interfaces to the RISC-V memory map with 4-state wait-state bus arbitration, plus physical 640x480 VGA display controller integration.',
    color: '#2563eb',
    tint: '#eff6ff',
    border: '#93c5fd',
  },
  {
    m: 'Akshit',
    initials: 'A',
    role: 'RV32M Hardware Datapath & Stall Logic',
    tag: 'Multi-cycle M · DSP MUL · Radix-2 Serial DIV',
    rtl: 'rv32m_unit.v · hazard_unit.v · forwarding_unit.v · cpu_core.v',
    desc: 'RV32M hardware datapath: DSP48E1 multiplier (2–3 cycles) and iterative 32-bit serial divider (~33 cycles). Pipeline hazard detection, forwarding bypass muxes, and multi-cycle stall logic.',
    color: '#7c3aed',
    tint: '#f5f3ff',
    border: '#c4b5fd',
  },
  {
    m: 'Aditya K',
    initials: 'AK',
    role: 'LOB Hardware Datapath & Order Parsing',
    tag: 'Hardware Order Parsing · Memory Controllers',
    rtl: 'lob_core.sv · lob_event_decoder.sv · lob_slot_table.sv · lob_price_ram.sv',
    desc: 'Limit Order Book hardware datapath, canonical order parsing, and dual-port BRAM memory controller logic. Fixed ~8–12 cycle datapath for complete BRAM read-match-write per order.',
    color: '#059669',
    tint: '#ecfdf5',
    border: '#6ee7b7',
  },
  {
    m: 'Aditya M',
    initials: 'AM',
    role: 'BRAM Priority Queues & Encoders',
    tag: 'Parallel BRAM Queues · O(1) Priority Encoders',
    rtl: 'lob_occupancy.sv · lob_bbo.sv · tb_lob_occupancy.sv · tb_lob_bbo.sv',
    desc: 'Physical BRAM priority queues, parallel multi-bank memory architecture, and O(1) hardware hierarchical priority encoders for dynamic instantaneous Best Bid/Offer tracking.',
    color: '#0891b2',
    tint: '#ecfeff',
    border: '#67e8f9',
  },
  {
    m: 'Aditeya G',
    initials: 'AG',
    role: 'Bare-Metal C Drivers & Telemetry',
    tag: '5 C-Program Workloads · Interrupts · Telemetry',
    rtl: 'bare-metal C test drivers · uart_telemetry.v · seven_seg_driver.v',
    desc: 'Bare-metal C-program drivers (5 synthetic trading workloads) used to validate accelerator I/O against edge cases. Software interrupt handling, UART streaming, and 7-segment telemetry output.',
    color: '#e11d48',
    tint: '#fff1f2',
    border: '#fda4af',
  },
]

const pipelineSteps = [
  {
    step: '1',
    author: 'Aditeya G',
    title: 'Workload Generation (C Drivers)',
    detail: 'Bare-metal C driver generates synthetic market orders on CPU',
    color: '#e11d48',
  },
  {
    step: '2',
    author: 'Aditya K',
    title: 'Order Parsing & LOB Datapath',
    detail: 'Canonical parsing & 8–12 cycle BRAM read-match-write FSM',
    color: '#059669',
  },
  {
    step: '3',
    author: 'Aditya M',
    title: 'BRAM Queues & Priority Encoders',
    detail: 'Parallel BRAM queues & O(1) encoders instantly extract Best Bid/Offer',
    color: '#0891b2',
  },
  {
    step: '4',
    author: 'Ronit',
    title: 'System Bus & MMIO Arbiter',
    detail: 'Maps LOB registers to RISC-V memory space with wait-state control',
    color: '#2563eb',
  },
  {
    step: '5',
    author: 'Akshit & Ronit',
    title: 'RV32M Core & VGA Display Output',
    detail: 'Softcore executes telemetry while FPGA VGA renders the live order book',
    color: '#7c3aed',
  },
]

const guarantees = [
  {
    title: 'Modular Hardware Development',
    color: '#059669',
    desc: 'Processor extensions and pure-hardware accelerator are designed in Verilog and independently verified in simulation before main bus integration.',
  },
  {
    title: 'Atomic Bus Contract & Zero Collisions',
    color: '#2563eb',
    desc: 'Zero memory collisions during dual-port BRAM read-modify-writes; 100% exact match against Python Golden I/O models on edge cases.',
  },
]

export default function Slide6() {
  return (
    <Frame n={6} kicker="Non-overlapping ownership · Group 9 Abstract" title="Team responsibilities & system partitioning">
      <Nut x={1730} y={75} />

      <div style={{ display: 'grid', gridTemplateColumns: '1070px 610px', gap: 48, marginTop: 18 }}>
        {/* LEFT COLUMN: 5-PERSON OWNERSHIP MATRIX */}
        <div>
          <div className="label rise" style={{ marginBottom: 10, ...delay(0.1) }}>
            Member responsibilities &amp; owned deliverables
          </div>

          <div style={{ display: 'flex', flexDirection: 'column', gap: 9 }}>
            {members.map((t, i) => (
              <div
                key={t.m}
                className="rise"
                style={{
                  background: '#ffffff',
                  border: '1.5px solid #e2e8f0',
                  borderLeft: `6px solid ${t.color}`,
                  padding: '11px 16px',
                  borderRadius: 6,
                  boxShadow: '0 2px 6px rgba(0,0,0,0.04)',
                  ...delay(0.16 + i * 0.06),
                }}
              >
                {/* Header row: Avatar, Name, Role, Tag */}
                <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 4 }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                    <div
                      style={{
                        width: 32,
                        height: 32,
                        borderRadius: '50%',
                        background: t.color,
                        color: '#ffffff',
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'center',
                        font: '700 14px var(--mono)',
                        flexShrink: 0,
                      }}
                    >
                      {t.initials}
                    </div>
                    <span style={{ font: '700 23px var(--font)', color: '#0f172a' }}>{t.m}</span>
                    <span style={{ font: '600 18px var(--font)', color: t.color, marginLeft: 4 }}>
                      — {t.role}
                    </span>
                  </div>
                  <span
                    style={{
                      font: '700 13px var(--mono)',
                      color: t.color,
                      background: t.tint,
                      border: `1px solid ${t.border}`,
                      padding: '3px 9px',
                      borderRadius: 4,
                    }}
                  >
                    {t.tag}
                  </span>
                </div>

                {/* RTL / Concrete deliverable line */}
                <div style={{ font: '600 13px var(--mono)', color: '#64748b', marginBottom: 4, paddingLeft: 42 }}>
                  {t.rtl}
                </div>

                {/* Description */}
                <p style={{ font: '400 16px/1.36 var(--font)', color: '#334155', margin: 0, paddingLeft: 42 }}>
                  {t.desc}
                </p>
              </div>
            ))}
          </div>
        </div>

        {/* RIGHT COLUMN: SEQUENTIAL DATA PIPELINE & GUARANTEES */}
        <div>
          <div className="label rise" style={{ marginBottom: 10, ...delay(0.14) }}>
            Hardware execution pipeline (strict sequential flow)
          </div>

          {/* VERTICAL PIPELINE WHERE EACH STAGE TRULY FOLLOWS THE PREVIOUS */}
          <div
            className="rise"
            style={{
              background: '#ffffff',
              border: '1.5px solid #e2e8f0',
              padding: '12px 14px',
              borderRadius: 6,
              boxShadow: '0 2px 6px rgba(0,0,0,0.04)',
              ...delay(0.24),
            }}
          >
            {pipelineSteps.map((p, i) => (
              <div key={p.step}>
                <div
                  style={{
                    display: 'flex',
                    alignItems: 'center',
                    gap: 12,
                    background: '#f8fafc',
                    border: '1px solid #e2e8f0',
                    borderLeft: `4px solid ${p.color}`,
                    padding: '8px 12px',
                    borderRadius: 4,
                  }}
                >
                  <div
                    style={{
                      width: 26,
                      height: 26,
                      borderRadius: '50%',
                      background: p.color,
                      color: '#fff',
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'center',
                      font: '700 14px var(--mono)',
                      flexShrink: 0,
                    }}
                  >
                    {p.step}
                  </div>
                  <div style={{ flex: 1 }}>
                    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                      <span style={{ font: '700 16px var(--font)', color: '#0f172a' }}>{p.title}</span>
                      <span style={{ font: '700 12px var(--mono)', color: p.color }}>{p.author}</span>
                    </div>
                    <div style={{ font: '400 13px var(--font)', color: '#475569', marginTop: 1 }}>{p.detail}</div>
                  </div>
                </div>

                {i < pipelineSteps.length - 1 && (
                  <div style={{ display: 'flex', justifyContent: 'center', padding: '3px 0' }}>
                    <svg width="18" height="15" viewBox="0 0 18 15">
                      <line x1="9" y1="0" x2="9" y2="9" stroke="#94a3b8" strokeWidth="2" />
                      <polygon points="5,8 13,8 9,14" fill="#64748b" />
                    </svg>
                  </div>
                )}
              </div>
            ))}
          </div>

          {/* ARCHITECTURAL GUARANTEES */}
          <div style={{ display: 'flex', flexDirection: 'column', gap: 9, marginTop: 12 }}>
            {guarantees.map((g, i) => (
              <div
                key={g.title}
                className="rise"
                style={{
                  background: '#ffffff',
                  border: '1.5px solid #e2e8f0',
                  borderLeft: `5px solid ${g.color}`,
                  padding: '11px 15px',
                  borderRadius: 6,
                  boxShadow: '0 2px 6px rgba(0,0,0,0.04)',
                  ...delay(0.52 + i * 0.08),
                }}
              >
                <div style={{ font: '700 14px var(--mono)', color: g.color, textTransform: 'uppercase', letterSpacing: '.05em', marginBottom: 2 }}>
                  {g.title}
                </div>
                <p style={{ font: '400 14px/1.35 var(--font)', color: '#334155', margin: 0 }}>
                  {g.desc}
                </p>
              </div>
            ))}
          </div>
        </div>
      </div>
    </Frame>
  )
}
