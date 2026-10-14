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
  },
  {
    m: 'Akshit',
    initials: 'A',
    role: 'RV32M Hardware Datapath & Stall Logic',
    tag: 'Multi-cycle M · DSP MUL · Radix-2 Serial DIV',
    rtl: 'rv32m_unit.v · hazard_unit.v · forwarding_unit.v · cpu_core.v',
    desc: 'RV32M hardware datapath: DSP48E1 multiplier (2–3 cycles) and iterative 32-bit serial divider (~33 cycles). Pipeline hazard detection, forwarding bypass muxes, and multi-cycle stall logic.',
  },
  {
    m: 'Aditya K',
    initials: 'AK',
    role: 'LOB Hardware Datapath & Order Parsing',
    tag: 'Hardware Order Parsing · Memory Controllers',
    rtl: 'lob_core.sv · lob_event_decoder.sv · lob_slot_table.sv · lob_price_ram.sv',
    desc: 'Limit Order Book hardware datapath, canonical order parsing, and dual-port BRAM memory controller logic. Fixed ~8–12 cycle datapath for complete BRAM read-match-write per order.',
  },
  {
    m: 'Aditya M',
    initials: 'AM',
    role: 'BRAM Priority Queues & Encoders',
    tag: 'Parallel BRAM Queues · O(1) Priority Encoders',
    rtl: 'lob_occupancy.sv · lob_bbo.sv · tb_lob_occupancy.sv · tb_lob_bbo.sv',
    desc: 'Physical BRAM priority queues, parallel multi-bank memory architecture, and O(1) hardware hierarchical priority encoders for dynamic instantaneous Best Bid/Offer tracking.',
  },
  {
    m: 'Aditeya G',
    initials: 'AG',
    role: 'Bare-Metal C Drivers & Telemetry',
    tag: '5 C-Program Workloads · Interrupts · Telemetry',
    rtl: 'bare-metal C test drivers · uart_telemetry.v · seven_seg_driver.v',
    desc: 'Bare-metal C-program drivers (5 synthetic trading workloads) used to validate accelerator I/O against edge cases. Software interrupt handling, UART streaming, and 7-segment telemetry output.',
  },
]

const pipelineSteps = [
  {
    step: '01',
    author: 'Aditeya G',
    title: 'Workload Generation (C Drivers)',
    detail: 'Bare-metal C driver generates synthetic market orders on CPU',
  },
  {
    step: '02',
    author: 'Aditya K',
    title: 'Order Parsing & LOB Datapath',
    detail: 'Canonical parsing & 8–12 cycle BRAM read-match-write FSM',
  },
  {
    step: '03',
    author: 'Aditya M',
    title: 'BRAM Queues & Priority Encoders',
    detail: 'Parallel BRAM queues & O(1) encoders instantly extract Best Bid/Offer',
  },
  {
    step: '04',
    author: 'Ronit',
    title: 'System Bus & MMIO Arbiter',
    detail: 'Maps LOB registers to RISC-V memory space with wait-state control',
  },
  {
    step: '05',
    author: 'Akshit & Ronit',
    title: 'RV32M Core & VGA Display Output',
    detail: 'Softcore executes telemetry while FPGA VGA renders the live order book',
  },
]

const guarantees = [
  {
    title: 'MODULAR HARDWARE DEVELOPMENT',
    desc: 'Processor extensions and pure-hardware accelerator are designed in Verilog and independently verified in simulation before main bus integration.',
  },
  {
    title: 'ATOMIC BUS CONTRACT & ZERO COLLISIONS',
    desc: 'Zero memory collisions during dual-port BRAM read-modify-writes; 100% exact match against Python Golden I/O models on edge cases.',
  },
]

export default function Slide6() {
  return (
    <Frame n={11} kicker="Non-overlapping ownership · Group 9 Abstract" title="Team responsibilities & system partitioning">
      <Nut x={1730} y={75} />

      <div style={{ display: 'grid', gridTemplateColumns: '1070px 610px', gap: 48, marginTop: 18 }}>
        {/* LEFT COLUMN: 5-PERSON OWNERSHIP MATRIX */}
        <div>
          <div className="label rise" style={{ marginBottom: 10, ...delay(0.1) }}>
            Member responsibilities &amp; owned deliverables
          </div>

          <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
            {members.map((t, i) => (
              <div
                key={t.m}
                className="rise"
                style={{
                  background: 'rgba(255, 255, 255, .65)',
                  border: '1.5px solid #c4c4c0',
                  borderLeft: '4px solid var(--navy)',
                  padding: '12px 18px',
                  borderRadius: 4,
                  boxShadow: '0 1px 4px rgba(0,0,0,0.03)',
                  ...delay(0.16 + i * 0.06),
                }}
              >
                {/* Header row: Initials badge, Name, Role, Tag */}
                <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 5 }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
                    <div
                      style={{
                        width: 32,
                        height: 32,
                        border: '1.5px solid var(--navy)',
                        borderRadius: 3,
                        background: '#e3e4f4',
                        color: 'var(--navy)',
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'center',
                        font: '700 13px var(--mono)',
                        flexShrink: 0,
                      }}
                    >
                      {t.initials}
                    </div>
                    <span style={{ font: '700 23px var(--font)', color: 'var(--ink)' }}>{t.m}</span>
                    <span style={{ font: '500 18px var(--font)', color: 'var(--ink-2)', marginLeft: 4 }}>
                      — {t.role}
                    </span>
                  </div>
                  <span
                    style={{
                      font: '600 13px var(--mono)',
                      color: 'var(--navy)',
                      background: '#e3e4f4',
                      border: '1px solid var(--navy)',
                      padding: '3px 10px',
                      borderRadius: 3,
                      letterSpacing: '.03em',
                    }}
                  >
                    {t.tag}
                  </span>
                </div>

                {/* RTL / Concrete deliverable line */}
                <div style={{ font: '500 13.5px var(--mono)', color: 'var(--navy)', marginBottom: 4, paddingLeft: 44 }}>
                  {t.rtl}
                </div>

                {/* Description */}
                <p style={{ font: '400 16px/1.38 var(--font)', color: 'var(--ink-2)', margin: 0, paddingLeft: 44 }}>
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

          {/* VERTICAL PIPELINE */}
          <div
            className="rise"
            style={{
              background: 'rgba(255, 255, 255, .65)',
              border: '1.5px solid #c4c4c0',
              padding: '14px 16px',
              borderRadius: 4,
              boxShadow: '0 1px 4px rgba(0,0,0,0.03)',
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
                    background: 'rgba(255, 255, 255, .8)',
                    border: '1.2px solid #cbd5e1',
                    borderLeft: '3px solid var(--navy)',
                    padding: '8px 12px',
                    borderRadius: 3,
                  }}
                >
                  <div
                    style={{
                      width: 28,
                      height: 28,
                      border: '1.2px solid var(--navy)',
                      borderRadius: 2,
                      background: '#e3e4f4',
                      color: 'var(--navy)',
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
                      <span style={{ font: '600 16px var(--font)', color: 'var(--ink)' }}>{p.title}</span>
                      <span style={{ font: '600 12px var(--mono)', color: 'var(--navy)' }}>{p.author}</span>
                    </div>
                    <div style={{ font: '400 13px var(--font)', color: 'var(--ink-2)', marginTop: 2 }}>{p.detail}</div>
                  </div>
                </div>

                {i < pipelineSteps.length - 1 && (
                  <div style={{ display: 'flex', justifyContent: 'center', padding: '3px 0' }}>
                    <svg width="18" height="15" viewBox="0 0 18 15">
                      <line x1="9" y1="0" x2="9" y2="9" stroke="var(--ink-3)" strokeWidth="1.8" />
                      <polygon points="5,8 13,8 9,14" fill="var(--navy)" />
                    </svg>
                  </div>
                )}
              </div>
            ))}
          </div>

          {/* ARCHITECTURAL GUARANTEES */}
          <div style={{ display: 'flex', flexDirection: 'column', gap: 10, marginTop: 14 }}>
            {guarantees.map((g, i) => (
              <div
                key={g.title}
                className="rise"
                style={{
                  background: 'rgba(255, 255, 255, .65)',
                  border: '1.5px solid #c4c4c0',
                  borderLeft: '4px solid var(--navy)',
                  padding: '12px 16px',
                  borderRadius: 4,
                  boxShadow: '0 1px 4px rgba(0,0,0,0.03)',
                  ...delay(0.52 + i * 0.08),
                }}
              >
                <div style={{ font: '600 14px var(--mono)', color: 'var(--navy)', letterSpacing: '.06em', marginBottom: 4 }}>
                  {g.title}
                </div>
                <p style={{ font: '400 14.5px/1.36 var(--font)', color: 'var(--ink-2)', margin: 0 }}>
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
