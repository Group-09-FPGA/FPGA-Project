import { useEffect, useState } from 'react'
import { BUBBLES, CAPTIONS, CYCLES, ROWS, type Kind } from '../data/trace'

const LEGEND: { k: Kind | 'FWD' | 'BUBBLE'; label: string; desc: string }[] = [
  { k: 'IF', label: 'IF', desc: 'Instruction Fetch' },
  { k: 'ID', label: 'ID', desc: 'Decode & Reg Read' },
  { k: 'EX', label: 'EX', desc: 'ALU / Branch Execute' },
  { k: 'M', label: 'M (BUSY)', desc: 'RV32M Multi-Cycle Op' },
  { k: 'WB', label: 'WB', desc: 'Writeback / Memory' },
  { k: 'HOLD', label: 'HOLD', desc: 'Skid Buffer Held' },
  { k: 'BUBBLE', label: '×', desc: 'Hazard Bubble' },
  { k: 'FWD', label: 'FWD', desc: 'Forwarded Operand' },
]

export default function Slide5_TimingDiagram() {
  const [cur, setCur] = useState(0)
  const [playing, setPlaying] = useState(false)

  useEffect(() => {
    if (!playing) return
    const id = setInterval(() => {
      setCur((c) => {
        if (c >= CYCLES - 1) {
          setPlaying(false)
          return c
        }
        return c + 1
      })
    }, 600)
    return () => clearInterval(id)
  }, [playing])

  const cols = Array.from({ length: CYCLES }, (_, i) => i)

  return (
    <div style={{ position: 'relative', width: 1760, height: 860, margin: '20px auto 0' }}>
      {/* ── Subtitle banner ── */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 12 }}>
        <div style={{ font: '600 15px var(--mono)', color: 'var(--navy)' }}>
          Real RTL Simulation Trace (tb_rv32m_pipeline.v) · Non-Idealized Multi-Cycle Execution (25 Cycles)
        </div>
        <div style={{ font: '500 14px var(--mono)', color: 'var(--ink-2)' }}>
          Target: Xilinx Artix-7 (100 MHz clk_core)
        </div>
      </div>

      {/* ── Main Timing Grid ── */}
      <div style={{ background: '#ffffff', border: '1.5px solid var(--line)', borderRadius: 4, padding: '16px 20px', position: 'relative' }}>
        <div style={{ display: 'grid', gridTemplateColumns: '360px repeat(25, 52px)', fontFamily: 'var(--mono)' }}>
          {/* Header row */}
          <div style={{ height: 36, display: 'flex', alignItems: 'center', fontWeight: 700, fontSize: 13, color: 'var(--ink-3)', borderBottom: '1.5px solid var(--line)' }}>
            INSTRUCTION (PC + ASM)
          </div>
          {cols.map((c) => (
            <div
              key={c}
              style={{
                height: 36,
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                fontWeight: 700,
                fontSize: 13,
                color: c === cur ? 'var(--navy)' : 'var(--ink-3)',
                borderBottom: '1.5px solid var(--line)',
                background: c === cur ? 'rgba(42, 46, 134, 0.08)' : 'transparent',
              }}
            >
              {c}
            </div>
          ))}

          {/* Trace Rows */}
          {ROWS.map((r) => (
            <TraceRowComponent key={r.pc} row={r} cur={cur} />
          ))}

          {/* Bubble row */}
          <div style={{ height: 40, display: 'flex', alignItems: 'center', fontSize: 13, color: 'var(--warn)', fontWeight: 600, borderBottom: '1px solid #e0e0dc' }}>
            Pipeline Hazard Bubble
          </div>
          {cols.map((c) => (
            <div
              key={c}
              style={{
                height: 40,
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                borderBottom: '1px solid #e0e0dc',
                opacity: c > cur ? 0.15 : 1,
              }}
            >
              {BUBBLES.includes(c) && (
                <span style={{ width: 44, height: 28, display: 'grid', placeItems: 'center', border: '1.5px solid var(--warn)', color: 'var(--warn)', fontSize: 16, fontWeight: 700 }}>
                  ×
                </span>
              )}
            </div>
          ))}
        </div>

        {/* Current Cycle Highlight Column Bar */}
        <div
          style={{
            position: 'absolute',
            top: 16,
            bottom: 16,
            left: 380 + cur * 52,
            width: 52,
            borderLeft: '2px solid var(--navy)',
            borderRight: '2px solid var(--navy)',
            background: 'rgba(42, 46, 134, 0.05)',
            pointerEvents: 'none',
            transition: 'left .25s ease-out',
          }}
        />
      </div>

      {/* ── Cycle Stepper Controls & Current Event Caption ── */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 20, marginTop: 16, background: '#ffffff', border: '1.5px solid var(--navy)', padding: '12px 20px', borderRadius: 4 }}>
        <button
          onClick={() => {
            if (cur >= CYCLES - 1) setCur(0)
            setPlaying((p) => !p)
          }}
          style={{
            font: '700 14px var(--mono)',
            padding: '8px 20px',
            background: playing ? 'var(--warn)' : 'var(--navy)',
            color: '#fff',
            border: 'none',
            borderRadius: 2,
            cursor: 'pointer',
          }}
        >
          {playing ? 'PAUSE' : 'PLAY TRACE'}
        </button>

        <button
          onClick={() => {
            setPlaying(false)
            setCur((c) => Math.max(0, c - 1))
          }}
          style={{ font: '600 14px var(--mono)', padding: '8px 16px', background: 'transparent', border: '1.5px solid var(--ink)', cursor: 'pointer' }}
        >
          ← PREV
        </button>

        <button
          onClick={() => {
            setPlaying(false)
            setCur((c) => Math.min(CYCLES - 1, c + 1))
          }}
          style={{ font: '600 14px var(--mono)', padding: '8px 16px', background: 'transparent', border: '1.5px solid var(--ink)', cursor: 'pointer' }}
        >
          NEXT →
        </button>

        <div style={{ font: '700 22px var(--mono)', color: 'var(--navy)', marginLeft: 8 }}>
          Cycle T{cur}
        </div>

        <div style={{ font: '500 17px var(--font)', color: 'var(--ink)', marginLeft: 16, flex: 1 }}>
          {CAPTIONS[cur]}
        </div>
      </div>

      {/* ── Legend ── */}
      <div style={{ display: 'flex', gap: 20, alignItems: 'center', marginTop: 14, flexWrap: 'wrap' }}>
        {LEGEND.map((l) => (
          <div key={l.k} style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
            <span style={getLegendSwatchStyle(l.k)}>{l.label}</span>
            <span style={{ font: '400 13px var(--mono)', color: 'var(--ink-2)' }}>{l.desc}</span>
          </div>
        ))}
      </div>

      {/* ── Bottom Technical Takeaways ── */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 24, marginTop: 16 }}>
        <div style={{ background: '#ffffff', border: '1.5px solid var(--line)', padding: '14px 18px', borderRadius: 4 }}>
          <div style={{ font: '700 13px var(--mono)', color: 'var(--navy)', letterSpacing: '.06em', textTransform: 'uppercase' }}>
            Multi-Cycle Hardware Latencies
          </div>
          <p style={{ font: '400 14px/1.4 var(--font)', color: 'var(--ink-2)', marginTop: 4 }}>
            <b>MUL stalls for 3 cycles</b> (3-stage pipelined array). <b>DIV stalls for 33 cycles</b> (32-iteration restoring recurrence loop). The FSM freezes EX and holds earlier instructions.
          </p>
        </div>

        <div style={{ background: '#ffffff', border: '1.5px solid var(--navy)', padding: '14px 18px', borderRadius: 4 }}>
          <div style={{ font: '700 13px var(--mono)', color: 'var(--navy)', letterSpacing: '.06em', textTransform: 'uppercase' }}>
            Front-End Skid Buffer Preservation
          </div>
          <p style={{ font: '400 14px/1.4 var(--font)', color: 'var(--ink-2)', marginTop: 4 }}>
            When an M-unit stall asserts, the front end holds the PC and latches the already-fetched instruction word in <code>if_buf</code>, preventing dropped or corrupted memory words.
          </p>
        </div>

        <div style={{ background: '#ffffff', border: '1.5px solid var(--line)', padding: '14px 18px', borderRadius: 4 }}>
          <div style={{ font: '700 13px var(--mono)', color: 'var(--navy)', letterSpacing: '.06em', textTransform: 'uppercase' }}>
            RAW Hazard Resolution via Forwarding
          </div>
          <p style={{ font: '400 14px/1.4 var(--font)', color: 'var(--ink-2)', marginTop: 4 }}>
            In Cycle 8, <code>add x4, x3, x1</code> forwards <code>x3</code> straight from Writeback into the ALU operand MUX, completely eliminating a 1-cycle data hazard bubble.
          </p>
        </div>
      </div>
    </div>
  )
}

function TraceRowComponent({ row, cur }: { row: (typeof ROWS)[number]; cur: number }) {
  return (
    <>
      <div style={{ height: 38, display: 'flex', alignItems: 'center', fontSize: 13, borderBottom: '1px solid #e0e0dc', color: 'var(--ink)' }}>
        <span style={{ color: 'var(--ink-3)', marginRight: 10, width: 28 }}>{row.pc}</span>
        <b>{row.asm}</b>
      </div>
      {Array.from({ length: CYCLES }, (_, c) => {
        const k = row.cells[c]
        if (!k) {
          return <div key={c} style={{ height: 38, borderBottom: '1px solid #e0e0dc' }} />
        }
        const isFwd = row.fwd?.includes(c)
        const isCurrent = c === cur
        const label = k === 'HOLD' ? '–' : k === 'M' ? 'M' : k

        return (
          <div
            key={c}
            style={{
              height: 38,
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              borderBottom: '1px solid #e0e0dc',
              opacity: c > cur ? 0.15 : 1,
            }}
          >
            <span style={getCellStyle(k, isFwd, isCurrent)}>{label}</span>
          </div>
        )
      })}
    </>
  )
}

function getCellStyle(k: Kind, isFwd?: boolean, isCurrent?: boolean): React.CSSProperties {
  const base: React.CSSProperties = {
    width: 44,
    height: 28,
    display: 'grid',
    placeItems: 'center',
    fontWeight: 700,
    fontSize: 12,
    border: '1.5px solid var(--line)',
    boxShadow: isFwd ? '0 0 0 3px var(--ok)' : isCurrent ? '0 0 0 2px var(--navy)' : undefined,
  }

  switch (k) {
    case 'IF':
      return { ...base, background: '#ffffff', color: 'var(--ink)' }
    case 'ID':
      return { ...base, background: '#e5e6f5', color: 'var(--navy)', borderColor: 'var(--navy)' }
    case 'EX':
      return { ...base, background: 'var(--navy)', color: '#ffffff', borderColor: 'var(--navy)' }
    case 'M':
      return {
        ...base,
        background: 'repeating-linear-gradient(135deg, var(--navy) 0 4px, #5a5fb8 4px 8px)',
        color: '#ffffff',
        borderColor: 'var(--navy)',
      }
    case 'WB':
      return { ...base, background: 'var(--ink)', color: '#ffffff' }
    case 'HOLD':
      return { ...base, background: 'transparent', borderStyle: 'dashed', borderColor: '#8b8f98', color: '#8b8f98' }
    default:
      return base
  }
}

function getLegendSwatchStyle(k: Kind | 'FWD' | 'BUBBLE'): React.CSSProperties {
  const base: React.CSSProperties = {
    width: 28,
    height: 20,
    display: 'inline-grid',
    placeItems: 'center',
    fontSize: 10,
    fontWeight: 700,
    border: '1.5px solid var(--line)',
  }

  switch (k) {
    case 'IF':
      return { ...base, background: '#fff', color: 'var(--ink)' }
    case 'ID':
      return { ...base, background: '#e5e6f5', color: 'var(--navy)', borderColor: 'var(--navy)' }
    case 'EX':
      return { ...base, background: 'var(--navy)', color: '#fff' }
    case 'M':
      return { ...base, background: 'repeating-linear-gradient(135deg, var(--navy) 0 3px, #5a5fb8 3px 6px)', color: '#fff' }
    case 'WB':
      return { ...base, background: 'var(--ink)', color: '#fff' }
    case 'HOLD':
      return { ...base, borderStyle: 'dashed', color: '#8b8f98', background: 'transparent' }
    case 'BUBBLE':
      return { ...base, borderColor: 'var(--warn)', color: 'var(--warn)', background: 'transparent' }
    case 'FWD':
      return { ...base, border: '2px solid var(--ok)', color: 'var(--ok)', background: 'transparent' }
  }
}
