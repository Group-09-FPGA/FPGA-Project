import { DiagramDefs, ModuleBox, SignalWire, SubsystemGroup } from '../components/Primitives'

export default function Slide3_RV32M() {
  return (
    <div style={{ position: 'relative', width: 1760, height: 860, margin: '20px auto 0' }}>
      <svg className="svg-canvas" width="1760" height="740" viewBox="0 0 1760 740">
        <DiagramDefs />

        {/* ════════════════════════════════════════════════════════════════════
            LEFT: FSM STATE MACHINE (4 STATES)
           ════════════════════════════════════════════════════════════════════ */}
        <SubsystemGroup
          x={20}
          y={20}
          w={600}
          h={700}
          label="1. Execution Control FSM (rv32m_unit.v)"
          sub="Single-Cycle Start Strobe · Handshake with CPU Pipeline"
          isNew
        />

        {/* State Bubbles */}
        {/* IDLE */}
        <g>
          <circle cx={320} cy={110} r={55} fill="#ffffff" stroke="var(--ink)" strokeWidth={2.4} />
          <text x={320} y={105} textAnchor="middle" style={{ font: '700 18px var(--mono)', fill: 'var(--ink)' }}>STATE_IDLE</text>
          <text x={320} y={126} textAnchor="middle" style={{ font: '500 13px var(--mono)', fill: 'var(--ink-2)' }}>2'b00 · Waiting</text>
        </g>

        {/* MULT */}
        <g>
          <circle cx={160} cy={310} r={58} fill="#e4e6f8" stroke="var(--navy)" strokeWidth={2.6} />
          <text x={160} y={305} textAnchor="middle" style={{ font: '700 18px var(--mono)', fill: 'var(--navy)' }}>STATE_MULT</text>
          <text x={160} y={326} textAnchor="middle" style={{ font: '600 13px var(--mono)', fill: 'var(--navy)' }}>2'b01 · 3 Clocks</text>
        </g>

        {/* DIV */}
        <g>
          <circle cx={480} cy={310} r={58} fill="#fceee8" stroke="var(--warn)" strokeWidth={2.6} />
          <text x={480} y={305} textAnchor="middle" style={{ font: '700 18px var(--mono)', fill: 'var(--warn)' }}>STATE_DIV</text>
          <text x={480} y={326} textAnchor="middle" style={{ font: '600 13px var(--mono)', fill: 'var(--warn)' }}>2'b10 · 33 Clocks</text>
        </g>

        {/* DONE */}
        <g>
          <circle cx={320} cy={510} r={58} fill="#e8f6ed" stroke="var(--ok)" strokeWidth={2.6} />
          <text x={320} y={505} textAnchor="middle" style={{ font: '700 18px var(--mono)', fill: 'var(--ok)' }}>STATE_DONE</text>
          <text x={320} y={526} textAnchor="middle" style={{ font: '600 13px var(--mono)', fill: 'var(--ok)' }}>2'b11 · Hold Result</text>
        </g>

        {/* FSM Transitions */}
        {/* IDLE -> MULT */}
        <SignalWire
          d="M275,142 L198,260"
          color="navy"
          width={2.2}
          label="start &amp;&amp; !funct3[2] (MUL*)"
          lx={180}
          ly={190}
        />

        {/* IDLE -> DIV */}
        <SignalWire
          d="M365,142 L442,260"
          color="warn"
          width={2.2}
          label="start &amp;&amp; funct3[2] (DIV*/REM*)"
          lx={470}
          ly={190}
        />

        {/* MULT -> DONE */}
        <SignalWire
          d="M198,360 L275,475"
          color="navy"
          width={2.2}
          label="mult_cnt == 1 (3rd clock edge)"
          lx={190}
          ly={435}
        />

        {/* DIV -> DONE */}
        <SignalWire
          d="M442,360 L365,475"
          color="warn"
          width={2.2}
          label="div_cnt == 31 (33rd clock edge)"
          lx={455}
          ly={435}
        />

        {/* DONE -> IDLE */}
        <SignalWire
          d="M320,452 V168"
          color="ink"
          width={2.2}
          label="!stall_pipeline (Pipeline accepts result)"
          lx={320}
          ly={380}
        />

        {/* Status flags callout */}
        <div style={{ position: 'absolute', left: 40, top: 590, width: 560 }}>
          <div style={{ background: '#ffffff', border: '1px solid #c8c8c0', padding: '14px 18px', borderRadius: 4 }}>
            <div style={{ font: '700 13px var(--mono)', color: 'var(--ink)', letterSpacing: '.06em' }}>
              HANDSHAKE SIGNALS
            </div>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '8px 24px', marginTop: 8, font: '400 13px var(--mono)' }}>
              <div><code>busy = (MULT || DIV)</code></div>
              <div><code>done = (state == DONE)</code></div>
              <div><code>stall_pipeline = m_stalling</code></div>
              <div><code>result = result_reg (held)</code></div>
            </div>
          </div>
        </div>

        {/* ════════════════════════════════════════════════════════════════════
            RIGHT TOP: 3-STAGE PIPELINED MULTIPLIER
           ════════════════════════════════════════════════════════════════════ */}
        <SubsystemGroup
          x={650}
          y={20}
          w={1090}
          h={300}
          label="2. Pipelined Multiplier (3 Clock Cycles)"
          sub="Supports MUL, MULH (signed×signed), MULHSU (signed×unsigned), MULHU (unsigned×unsigned)"
          isNew
        />

        {/* Stage 1 */}
        <ModuleBox
          x={680}
          y={70}
          w={290}
          h={120}
          title="Stage 1: Operand Ext"
          subtitle="Signed / Unsigned Ext"
          detail="ext_a[32:0] = sign_a ? {op1[31], op1} : {0, op1}&#10;ext_b[32:0] = sign_b ? {op2[31], op2} : {0, op2}&#10;Latches: mult_reg_a, mult_reg_b, mult_op_r1"
          isNew
          tag="CYCLE 1"
        />

        {/* Stage 2 */}
        <ModuleBox
          x={1040}
          y={70}
          w={310}
          h={120}
          title="Stage 2: 66-Bit Product"
          subtitle="DSP48 / Logic Array Multiplier"
          detail="mult_prod_r2[65:0] <= mult_reg_a * mult_reg_b&#10;Latches 66-bit signed product&#10;Pipelined to meet 100 MHz Artix-7 timing"
          isNew
          tag="CYCLE 2"
        />

        {/* Stage 3 */}
        <ModuleBox
          x={1420}
          y={70}
          w={290}
          h={120}
          title="Stage 3: Result Select"
          subtitle="Lower vs Upper 32 Bits"
          detail="MUL   → mult_prod_r2[31:0]&#10;MULH* → mult_prod_r2[63:32]&#10;Stores into architectural result_reg"
          isNew
          tag="CYCLE 3"
        />

        {/* Multiplier Interconnections */}
        <SignalWire d="M970,130 H1038" color="navy" label="33b extended" lx={1004} ly={118} width={2.2} />
        <SignalWire d="M1350,130 H1418" color="navy" label="66b product" lx={1384} ly={118} width={2.2} />

        {/* Multiplier timing note */}
        <text x={680} y={230} style={{ font: '600 14px var(--mono)', fill: 'var(--navy)' }}>
          Cycle Progression:
        </text>
        <text x={840} y={230} style={{ font: '500 13px var(--mono)', fill: 'var(--ink-2)' }}>
          Clock 0 (Fetch/ID) → Clock 1 (Stage 1 Latch) → Clock 2 (Multiply) → Clock 3 (Done, Result Valid)
        </text>
        <text x={680} y={260} style={{ font: '600 13px var(--mono)', fill: 'var(--ok)' }}>
          Total Pipeline Stall: Exactly 3 cycles. Met timing at 100 MHz with +0.420 ns positive slack.
        </text>

        {/* ════════════════════════════════════════════════════════════════════
            RIGHT BOTTOM: 32-ITERATION RESTORING DIVIDER
           ════════════════════════════════════════════════════════════════════ */}
        <SubsystemGroup
          x={650}
          y={340}
          w={1090}
          h={380}
          label="3. 32-Iteration Restoring Divider (33 Clock Cycles)"
          sub="Supports DIV, DIVU, REM, REMU with Corner-Case Detection (Div-by-Zero & Overflow)"
          isNew
        />

        {/* Init Block */}
        <ModuleBox
          x={680}
          y={390}
          w={280}
          h={140}
          title="Initialization (Clock 1)"
          subtitle="Absolute Value &amp; Sign Latch"
          detail="quo_reg <= abs(op1)&#10;div_reg <= abs(op2)&#10;rem_reg <= 32'd0&#10;div_zero <= (op2 == 0)&#10;overflow <= (op1 == INT_MIN &amp;&amp; op2 == -1)"
          isNew
          tag="INIT"
        />

        {/* Iteration Block */}
        <ModuleBox
          x={1030}
          y={390}
          w={350}
          h={140}
          title="Recurrence Loop (Clocks 2–32)"
          subtitle="1 Quotient Bit per Clock (32 iters)"
          detail="shifted_rem = {rem_reg, quo_reg[31]}&#10;trial_sub = shifted_rem - div_reg&#10;borrow = trial_sub[33]&#10;rem_reg <= borrow ? shifted : trial_sub&#10;quo_reg <= {quo_reg[30:0], ~borrow}"
          isNew
          tag="ITER ×32"
        />

        {/* Correction Block */}
        <ModuleBox
          x={1450}
          y={390}
          w={260}
          h={140}
          title="Correction &amp; Exceptions"
          subtitle="Clock 33 (cnt == 31)"
          detail="Div-by-Zero → 0xFFFF_FFFF&#10;Overflow → 0x8000_0000&#10;Sign negation for DIV/REM&#10;Latches final architectural result"
          isNew
          tag="FINAL"
        />

        <SignalWire d="M960,460 H1028" color="warn" label="abs values" lx={994} ly={446} width={2.2} />
        <SignalWire d="M1380,460 H1448" color="warn" label="32-bit raw" lx={1414} ly={446} width={2.2} />

        {/* Truth Table */}
        <div style={{ position: 'absolute', left: 680, top: 560, width: 1030 }}>
          <table style={{ width: '100%', borderCollapse: 'collapse', font: '13px var(--mono)' }}>
            <thead>
              <tr style={{ borderBottom: '1.5px solid var(--line)', textAlign: 'left', color: 'var(--ink-3)' }}>
                <th style={{ padding: '6px 8px' }}>funct3</th>
                <th style={{ padding: '6px 8px' }}>Instruction</th>
                <th style={{ padding: '6px 8px' }}>Operation</th>
                <th style={{ padding: '6px 8px' }}>Div-by-Zero Result</th>
                <th style={{ padding: '6px 8px' }}>Overflow Result</th>
                <th style={{ padding: '6px 8px' }}>Latency</th>
              </tr>
            </thead>
            <tbody>
              {[
                ['000', 'MUL', 'op1 × op2 [31:0]', '—', '—', '3 cycles'],
                ['001', 'MULH', 'signed(op1) × signed(op2) [63:32]', '—', '—', '3 cycles'],
                ['010', 'MULHSU', 'signed(op1) × unsigned(op2) [63:32]', '—', '—', '3 cycles'],
                ['011', 'MULHU', 'unsigned(op1) × unsigned(op2) [63:32]', '—', '—', '3 cycles'],
                ['100', 'DIV', 'signed(op1) / signed(op2)', '0xFFFF_FFFF (-1)', '0x8000_0000', '33 cycles'],
                ['101', 'DIVU', 'unsigned(op1) / unsigned(op2)', '0xFFFF_FFFF (max)', '—', '33 cycles'],
                ['110', 'REM', 'signed(op1) % signed(op2)', 'op1', '0x0000_0000', '33 cycles'],
                ['111', 'REMU', 'unsigned(op1) % unsigned(op2)', 'op1', '—', '33 cycles'],
              ].map(([f3, inst, op, dbz, ovf, lat]) => (
                <tr key={inst} style={{ borderBottom: '1px solid #e0e0dc' }}>
                  <td style={{ padding: '4px 8px', color: 'var(--navy)', fontWeight: 600 }}>{f3}</td>
                  <td style={{ padding: '4px 8px', color: 'var(--ink)', fontWeight: 700 }}>{inst}</td>
                  <td style={{ padding: '4px 8px', color: 'var(--ink-2)' }}>{op}</td>
                  <td style={{ padding: '4px 8px', color: dbz !== '—' ? 'var(--warn)' : 'var(--ink-3)' }}>{dbz}</td>
                  <td style={{ padding: '4px 8px', color: ovf !== '—' ? 'var(--warn)' : 'var(--ink-3)' }}>{ovf}</td>
                  <td style={{ padding: '4px 8px', color: 'var(--ok)', fontWeight: 600 }}>{lat}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </svg>
    </div>
  )
}
