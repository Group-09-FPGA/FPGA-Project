import { DiagramDefs, ModuleBox, Mux2to1, SignalWire, SubsystemGroup } from '../components/Primitives'

export default function Slide4_Divider() {
  return (
    <div style={{ position: 'relative', width: 1760, height: 860, margin: '20px auto 0' }}>
      <svg className="svg-canvas" width="1760" height="740" viewBox="0 0 1760 740">
        <DiagramDefs />

        {/* ════════════════════════════════════════════════════════════════════
            PHASE 1: INPUT CONDITIONING, ABSOLUTE VALUE & FLAGS (CLOCK 1)
           ════════════════════════════════════════════════════════════════════ */}
        <SubsystemGroup
          x={20}
          y={20}
          w={460}
          h={680}
          label="Phase 1 · Input Conditioning &amp; Corner-Case Latch (Clock 1)"
          sub="Absolute Value MUXes · Div-by-Zero &amp; Overflow Flags"
          isNew
        />

        {/* Inputs */}
        <ModuleBox x={40} y={60} w={150} h={54} title="Operand 1 (op1)" subtitle="rs1[31:0] (Dividend)" detail="Signed or Unsigned" tag="32-BIT" />
        <ModuleBox x={40} y={130} w={150} h={54} title="Operand 2 (op2)" subtitle="rs2[31:0] (Divisor)" detail="Signed or Unsigned" tag="32-BIT" />
        <ModuleBox x={40} y={200} w={150} h={54} title="Funct3 Select" subtitle="funct3[2:0]" detail="DIV, DIVU, REM, REMU" tag="3-BIT" />

        {/* 2's Complement Negators */}
        <g>
          <rect x={220} y={60} width={90} height={54} rx={3} fill="#ffffff" stroke="#16181d" strokeWidth={1.5} />
          <text x={265} y={85} textAnchor="middle" style={{ font: '700 13px var(--mono)', fill: 'var(--ink)' }}>- op1</text>
          <text x={265} y={102} textAnchor="middle" style={{ font: '500 10px var(--mono)', fill: '#6e727e' }}>Negate 32b</text>

          <rect x={220} y={130} width={90} height={54} rx={3} fill="#ffffff" stroke="#16181d" strokeWidth={1.5} />
          <text x={265} y={155} textAnchor="middle" style={{ font: '700 13px var(--mono)', fill: 'var(--ink)' }}>- op2</text>
          <text x={265} y={172} textAnchor="middle" style={{ font: '500 10px var(--mono)', fill: '#6e727e' }}>Negate 32b</text>
        </g>

        {/* Absolute Value MUXes */}
        <Mux2to1 x={340} y={60} w={28} h={54} label="MUX" selLabel="op1_neg" />
        <Mux2to1 x={340} y={130} w={28} h={54} label="MUX" selLabel="op2_neg" />

        {/* Corner-Case & Sign Logic */}
        <ModuleBox
          x={40}
          y={280}
          w={420}
          h={150}
          title="Corner-Case &amp; Sign Detection Logic"
          subtitle="Combinational Pre-computation"
          detail="div_zero  = (op2 == 32'd0)&#10;overflow  = op1_is_signed &amp;&amp; (op1 == 32'h8000_0000) &amp;&amp; (op2 == 32'hFFFF_FFFF)&#10;neg_quo   = op1_is_signed &amp;&amp; (op1[31] ^ op2[31]) &amp;&amp; (op2 != 32'd0)&#10;neg_rem   = op1_is_signed &amp;&amp; op1[31] &amp;&amp; (op2 != 32'd0)&#10;orig_op1  = op1 (Preserved for Remainder-by-Zero rule)"
          tag="FLAGS"
        />

        {/* Initial Registers Latched on Clock 1 */}
        <ModuleBox
          x={40}
          y={460}
          w={420}
          h={220}
          title="Initial Recurrence Registers (Clock 1 ▲)"
          subtitle="Latched on (start &amp;&amp; funct3[2])"
          detail="rem_reg[31:0]  <= 32'd0 (Initial remainder cleared)&#10;quo_reg[31:0]  <= abs_op1 (Dividend loaded into quotient)&#10;div_reg[31:0]  <= abs_op2 (Divisor held constant)&#10;orig_op1[31:0] <= op1&#10;div_cnt[5:0]   <= 6'd0 (Resets 36-cycle iteration counter)&#10;div_op_r[2:0]  <= funct3&#10;busy <= 1'b1 · asserts m_stalling to freeze CPU pipeline"
          isNew
          tag="INIT REGS"
        />

        <SignalWire d="M190,87 H218" />
        <SignalWire d="M190,157 H218" />
        <SignalWire d="M310,87 H338" />
        <SignalWire d="M310,157 H338" />
        <SignalWire d="M368,87 H390 V458" label="abs_op1" lx={420} ly={240} width={2.2} />
        <SignalWire d="M368,157 H410 V458" label="abs_op2" lx={435} ly={260} width={2.2} />

        {/* ════════════════════════════════════════════════════════════════════
            PHASE 2: RESTORING RECURRENCE LOOP DATAPATH (CLOCKS 2–37)
           ════════════════════════════════════════════════════════════════════ */}
        <SubsystemGroup
          x={510}
          y={20}
          w={650}
          h={680}
          label="Phase 2 · Restoring Recurrence Datapath (Clocks 2–37 · 36 Iterations)"
          sub="Single Quotient Bit Generated per Clock Cycle · Restoring Remainder Feedback"
          isNew
        />

        {/* 33-bit Bit Concatenator & Left Shift */}
        <ModuleBox
          x={530}
          y={60}
          w={280}
          h={100}
          title="1-Bit Left Shifter &amp; Concatenator"
          subtitle="shifted_rem[32:0]"
          detail="{rem_reg[31:0], quo_reg[31]}&#10;Shifts remainder left by 1 bit and&#10;shifts in MSB of current quotient register"
          isNew
          tag="CONCAT"
        />

        {/* Divisor Register Constant */}
        <ModuleBox
          x={840}
          y={60}
          w={200}
          h={100}
          title="Divisor Register"
          subtitle="div_reg[31:0]"
          detail="Zero-extended to 34 bits:&#10;{2'b0, div_reg[31:0]}"
          isNew
          tag="32-BIT REG"
        />

        {/* 34-bit Trial Subtractor */}
        <ModuleBox
          x={580}
          y={190}
          w={410}
          h={100}
          title="34-bit Trial Subtractor"
          subtitle="trial_sub[33:0]"
          detail="trial_sub[33:0] = {1'b0, shifted_rem[32:0]} - {2'b0, div_reg[31:0]}&#10;Calculates tentative subtraction for this bit iteration&#10;trial_sub[33] = borrow bit (1 if negative, 0 if successful)"
          isNew
          tag="SUBTRACTOR"
        />

        {/* Borrow Detection */}
        <ModuleBox
          x={1020}
          y={190}
          w={120}
          h={100}
          title="Borrow Flag"
          subtitle="borrow = trial[33]"
          detail="1 = Underflow&#10;0 = Success"
          tag="BORROW"
        />

        {/* Remainder Restoring MUX */}
        <Mux2to1 x={660} y={320} w={32} h={80} label="MUX" selLabel="borrow" />
        <text x={710} y={345} style={{ font: '600 12px var(--mono)', fill: 'var(--ok)' }}>0: trial_sub[31:0] (Subtracted)</text>
        <text x={710} y={385} style={{ font: '600 12px var(--mono)', fill: 'var(--warn)' }}>1: shifted_rem[31:0] (RESTORED)</text>

        {/* Quotient Shift & Bit-Insert */}
        <ModuleBox
          x={840}
          y={320}
          w={300}
          h={80}
          title="Quotient Shift &amp; Append"
          subtitle="next_quo[31:0]"
          detail="next_quo = {quo_reg[30:0], ~borrow}&#10;Shifts quotient left and appends inverted borrow bit"
          isNew
          tag="SHIFT-IN"
        />

        {/* Recurrence Registers (Clocked Feedback Loop) */}
        <ModuleBox
          x={530}
          y={440}
          w={610}
          h={140}
          title="Recurrence State Registers (Clocked on Each Iteration ▲)"
          subtitle="Updated each clock while (div_cnt < 6'd35)"
          detail="rem_reg[31:0] <= next_rem (Restored remainder or trial subtraction result)&#10;quo_reg[31:0] <= next_quo (Quotient accumulator accumulating bits MSB to LSB)&#10;div_cnt       <= div_cnt + 6'd1 (Advances iteration count from 0 up to 35)&#10;Feedback loop iterates exactly once per cycle across 36 clock cycles"
          isNew
          tag="LOOP REGS"
        />

        {/* Feedback Wire Arrows */}
        <SignalWire d="M670,160 V188" />
        <SignalWire d="M940,160 V188" />
        <SignalWire d="M990,240 H1018" color="warn" label="trial[33]" lx={1004} ly={228} />
        <SignalWire d="M1080,290 V340 H1018" color="warn" label="borrow" lx={1060} ly={330} />
        <SignalWire d="M692,360 H838" color="ok" label="next_rem" lx={765} ly={350} width={2.2} />
        <SignalWire d="M835,580 V620 H510 V110 H528" color="navy" label="36-Cycle Iteration Feedback Loop" lx={670} ly={635} width={2.4} dashed flowAnim />

        {/* Iteration Counter */}
        <ModuleBox
          x={530}
          y={600}
          w={610}
          h={80}
          title="Iteration Counter (div_cnt[5:0])"
          subtitle="Sequence Control"
          detail="Cycles 2–37: Iteration loop active (div_cnt: 0 → 35)&#10;Cycle 38: div_cnt == 35 triggers final iteration and latch to Phase 3"
          tag="COUNTER"
        />

        {/* ════════════════════════════════════════════════════════════════════
            PHASE 3: POST-PROCESSING, SIGN CORRECTION & EXCEPTIONS (CLOCKS 38–39)
           ════════════════════════════════════════════════════════════════════ */}
        <SubsystemGroup
          x={1190}
          y={20}
          w={550}
          h={680}
          label="Phase 3 · Sign Correction, Exceptions &amp; Done Strobe (Clocks 38–39)"
          sub="RISC-V Div-by-Zero / Overflow Invariants · Output Latch"
          isNew
        />

        {/* Final Sign Inversion Units */}
        <g>
          <rect x={1210} y={60} width={130} height={70} rx={3} fill="#ffffff" stroke="#16181d" strokeWidth={1.5} />
          <text x={1275} y={85} textAnchor="middle" style={{ font: '700 13px var(--mono)', fill: 'var(--ink)' }}>- final_quo_u</text>
          <text x={1275} y={105} textAnchor="middle" style={{ font: '500 10px var(--mono)', fill: '#6e727e' }}>Quotient Negator</text>

          <rect x={1210} y={150} width={130} height={70} rx={3} fill="#ffffff" stroke="#16181d" strokeWidth={1.5} />
          <text x={1275} y={175} textAnchor="middle" style={{ font: '700 13px var(--mono)', fill: 'var(--ink)' }}>- final_rem_u</text>
          <text x={1275} y={195} textAnchor="middle" style={{ font: '500 10px var(--mono)', fill: '#6e727e' }}>Remainder Negator</text>
        </g>

        {/* Sign Correction MUXes */}
        <Mux2to1 x={1380} y={65} w={28} h={60} label="MUX" selLabel="neg_quo" />
        <text x={1415} y={85} style={{ font: '500 10px var(--mono)', fill: '#4a4e57' }}>0: quo_u</text>
        <text x={1415} y={110} style={{ font: '500 10px var(--mono)', fill: '#4a4e57' }}>1: -quo_u</text>

        <Mux2to1 x={1380} y={155} w={28} h={60} label="MUX" selLabel="neg_rem" />
        <text x={1415} y={175} style={{ font: '500 10px var(--mono)', fill: '#4a4e57' }}>0: rem_u</text>
        <text x={1415} y={200} style={{ font: '500 10px var(--mono)', fill: '#4a4e57' }}>1: -rem_u</text>

        {/* Priority Exception & Operation Multiplexer */}
        <ModuleBox
          x={1210}
          y={250}
          w={510}
          h={190}
          title="Exception Priority &amp; Operation Select MUX"
          subtitle="final_div_result[31:0] Multiplexer"
          detail="1. if (div_zero):&#10;     DIV / DIVU → 32'hFFFF_FFFF (-1 / max)&#10;     REM / REMU → orig_op1 (Preserves dividend)&#10;2. else if (overflow) [INT_MIN / -1]:&#10;     DIV → 32'h8000_0000 (INT_MIN)&#10;     REM → 32'h0000_0000&#10;3. else:&#10;     DIV  → final_quo   |  DIVU → final_quo_u&#10;     REM  → final_rem   |  REMU → final_rem_u"
          isNew
          tag="PRIORITY MUX"
        />

        {/* Architectural Output Register */}
        <ModuleBox
          x={1210}
          y={470}
          w={510}
          h={110}
          title="Architectural Result Register (Clock 39 ▲)"
          subtitle="result_reg[31:0] Latch"
          detail="result_reg <= final_div_result&#10;Latched on Clock 39 ▲ · Held stable for CPU pipeline&#10;Connects directly to EX Stage ex_result MUX"
          isNew
          tag="FINAL REG"
        />

        {/* Handshake Signals */}
        <ModuleBox
          x={1210}
          y={600}
          w={510}
          h={80}
          title="Pipeline Handshake &amp; Stall Release (Clock 39)"
          subtitle="Handshake Ports"
          detail="done = 1'b1 (Asserted on Clock 39) · busy = 1'b0 (Released)&#10;Deasserts m_stalling → stall_pipeline = 0 · CPU captures word into EX/WB"
          isNew
          tag="HANDSHAKE"
        />

        <SignalWire d="M1140,490 H1208" color="navy" label="final_iters" lx={1174} ly={476} width={2.2} />
        <SignalWire d="M1408,95 H1480 V248" />
        <SignalWire d="M1408,185 H1520 V248" />
        <SignalWire d="M1465,440 V468" color="navy" label="final_div_result[31:0]" lx={1465} ly={454} width={2.4} />
      </svg>
    </div>
  )
}
