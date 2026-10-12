import { DiagramDefs, ModuleBox, Mux2to1, SignalWire, SubsystemGroup } from '../components/Primitives'

export default function Slide4_Divider() {
  return (
    <div style={{ position: 'relative', width: 1760, height: 860, margin: '20px auto 0' }}>
      <svg className="svg-canvas" width="1760" height="760" viewBox="0 0 1760 760">
        <DiagramDefs />

        {/* ════════════════════════════════════════════════════════════════════
            STAGE 1: INPUT CONDITIONING, ABSOLUTE VALUES & CORNER CASES (CYCLE 1)
           ════════════════════════════════════════════════════════════════════ */}
        <SubsystemGroup
          x={20}
          y={15}
          w={440}
          h={725}
          label="Stage 1 · Input Conditioning &amp; Corner Cases (Cycle 1)"
          sub="Absolute Value MUXes · Corner-Case Detectors · Register Init"
          isNew
        />

        {/* Inputs */}
        <ModuleBox x={35} y={55} w={150} h={54} title="Operand 1 (op1)" subtitle="rs1[31:0] · Dividend" tag="32-BIT" />
        <ModuleBox x={35} y={125} w={150} h={54} title="Operand 2 (op2)" subtitle="rs2[31:0] · Divisor" tag="32-BIT" />
        <ModuleBox x={35} y={195} w={150} h={54} title="Operation (funct3)" subtitle="DIV / DIVU / REM / REMU" tag="3-BIT" />

        {/* 2's Complement Negators */}
        <g>
          <rect x={215} y={55} width={75} height={54} rx={3} fill="#ffffff" stroke="#16181d" strokeWidth={1.5} />
          <text x={252} y={80} textAnchor="middle" style={{ font: '700 13px var(--mono)', fill: 'var(--ink)' }}>- op1</text>
          <text x={252} y={97} textAnchor="middle" style={{ font: '500 10px var(--mono)', fill: '#6e727e' }}>~op1 + 1</text>

          <rect x={215} y={125} width={75} height={54} rx={3} fill="#ffffff" stroke="#16181d" strokeWidth={1.5} />
          <text x={252} y={150} textAnchor="middle" style={{ font: '700 13px var(--mono)', fill: 'var(--ink)' }}>- op2</text>
          <text x={252} y={167} textAnchor="middle" style={{ font: '500 10px var(--mono)', fill: '#6e727e' }}>~op2 + 1</text>
        </g>

        {/* Absolute Value MUXes */}
        <Mux2to1 x={315} y={55} w={28} h={54} label="MUX" selLabel="op1_neg" />
        <text x={350} y={73} style={{ font: '500 10px var(--mono)', fill: '#4a4e57' }}>1: -op1</text>
        <text x={350} y={97} style={{ font: '500 10px var(--mono)', fill: '#4a4e57' }}>0: op1</text>

        <Mux2to1 x={315} y={125} w={28} h={54} label="MUX" selLabel="op2_neg" />
        <text x={350} y={143} style={{ font: '500 10px var(--mono)', fill: '#4a4e57' }}>1: -op2</text>
        <text x={350} y={167} style={{ font: '500 10px var(--mono)', fill: '#4a4e57' }}>0: op2</text>

        {/* Wires to negators and MUXes */}
        <SignalWire d="M185,82 H213" />
        <SignalWire d="M185,152 H213" />
        <SignalWire d="M290,82 H313" />
        <SignalWire d="M290,152 H313" />

        {/* Corner-Case & Sign Logic Box */}
        <ModuleBox
          x={35}
          y={265}
          w={340}
          h={170}
          title="Corner-Case &amp; Sign Detector"
          subtitle="Combinational Predicates (Cycle 1)"
          detail="div_zero = (op2 == 32'd0)&#10;overflow = op1_is_signed &amp;&amp; (op1 == 80000000 &amp;&amp; op2 == FFFFFFFF)&#10;neg_quo  = op1_is_signed &amp;&amp; (op1[31] ^ op2[31]) &amp;&amp; (op2 != 0)&#10;neg_rem  = op1_is_signed &amp;&amp; op1[31] &amp;&amp; (op2 != 0)&#10;orig_op1 = op1 (Preserved for Rem-by-Zero)"
          tag="PREDICATES"
        />

        {/* Cycle 1 Latched Registers */}
        <ModuleBox
          x={35}
          y={455}
          w={410}
          h={265}
          title="Recurrence Init Registers (Cycle 1 ▲)"
          subtitle="Latched on (start &amp;&amp; funct3[2]) in STATE_IDLE"
          detail="rem_reg[31:0]  <= 32'd0 (Initial remainder cleared)&#10;quo_reg[31:0]  <= abs_op1 (Dividend loaded into quotient)&#10;div_reg[31:0]  <= abs_op2 (Divisor held constant)&#10;orig_op1[31:0] <= op1&#10;div_cnt[4:0]   <= 5'd0 (5-bit counter resets for 32 iterations)&#10;div_op_r[2:0]  <= funct3&#10;Latches: div_zero, overflow, neg_quo, neg_rem&#10;busy <= 1'b1 · asserts m_stalling to freeze CPU pipeline"
          isNew
          tag="INIT REGS"
        />

        {/* Vertical bypass wires down to Cycle 1 registers (avoiding the Predicates box) */}
        <SignalWire d="M343,82 H395 V452" label="abs_op1" lx={395} ly={240} width={2.2} />
        <SignalWire d="M343,152 H420 V452" label="abs_op2" lx={420} ly={258} width={2.2} />

        {/* ════════════════════════════════════════════════════════════════════
            STAGE 2: 32-ITERATION RESTORING RECURRENCE LOOP DATAPATH (CYCLES 2–32)
           ════════════════════════════════════════════════════════════════════ */}
        <SubsystemGroup
          x={480}
          y={15}
          w={730}
          h={725}
          label="Stage 2 · 32-Iteration Restoring Recurrence Datapath (Cycles 2–32)"
          sub="Single Bit / Cycle · 34-bit Trial Subtraction · Remainder Restoration MUX"
          isNew
        />

        {/* Recurrence Registers at top */}
        <ModuleBox x={495} y={55} w={215} h={74} title="rem_reg[31:0]" subtitle="Accumulated Remainder" tag="REG 32b" isNew />
        <ModuleBox x={735} y={55} w={215} h={74} title="quo_reg[31:0]" subtitle="Quotient Shift Register" tag="REG 32b" isNew />
        <ModuleBox x={975} y={55} w={215} h={74} title="div_reg[31:0]" subtitle="Divisor Constant" tag="REG 32b" isNew />

        {/* Left Shifter & Divisor Extension */}
        <ModuleBox
          x={510}
          y={165}
          w={340}
          h={75}
          title="1-Bit Left Shifter &amp; Concat"
          subtitle="shifted_rem[32:0] = {rem_reg[31:0], quo_reg[31]}"
          detail="Shifts remainder left by 1 bit and shifts in MSB of current quotient"
          tag="CONCAT"
          isNew
        />

        <ModuleBox
          x={910}
          y={165}
          w={260}
          h={75}
          title="Divisor Zero-Extension"
          subtitle="{2'b00, div_reg[31:0]}"
          detail="Zero-extends 32-bit divisor to 34-bit subtrahend"
          tag="EXTEND"
        />

        <SignalWire d="M602,129 V163" />
        <SignalWire d="M842,129 V150 H750 V163" label="quo_reg[31]" lx={790} ly={142} />
        <SignalWire d="M1082,129 V163" />

        {/* 34-bit Trial Subtractor */}
        <ModuleBox
          x={530}
          y={275}
          w={480}
          h={82}
          title="34-Bit Trial Subtractor"
          subtitle="trial_sub[33:0] = {1'b0, shifted_rem} - {2'b0, div_reg}"
          detail="trial_sub[33] = borrow bit (1 = negative / underflow, 0 = successful subtraction)"
          tag="SUBTRACTOR 34b"
          isNew
        />

        {/* Borrow Flag Box */}
        <ModuleBox
          x={1040}
          y={275}
          w={150}
          h={82}
          title="Borrow Flag"
          subtitle="borrow = trial[33]"
          detail="1: Restore&#10;0: Subtract"
          tag="BORROW"
        />

        <SignalWire d="M680,240 V273" />
        <SignalWire d="M1040,240 V260 H870 V273" />
        <SignalWire d="M1010,316 H1038" color="warn" label="trial[33]" lx={1024} ly={306} />

        {/* Remainder Restoring MUX */}
        <Mux2to1 x={610} y={390} w={32} h={80} label="MUX" selLabel="borrow" />
        <text x={655} y={415} style={{ font: '600 11px var(--mono)', fill: 'var(--ok)' }}>0: trial_sub[31:0] (Subtracted)</text>
        <text x={655} y={445} style={{ font: '600 11px var(--mono)', fill: 'var(--warn)' }}>1: shifted_rem[31:0] (RESTORED)</text>

        {/* Quotient Shift & Bit Insert */}
        <ModuleBox
          x={780}
          y={390}
          w={310}
          h={80}
          title="Quotient Shift &amp; Bit Insert"
          subtitle="next_quo[31:0] = {quo_reg[30:0], ~borrow}"
          detail="Shifts quotient left by 1 and inserts inverted borrow at LSB"
          tag="SHIFT-IN"
          isNew
        />

        <SignalWire d="M720,357 V390 H642" />
        <SignalWire d="M1115,357 V410 H1092" color="warn" label="borrow" lx={1105} ly={398} />
        <SignalWire d="M1040,430 H1090" color="ok" label="~borrow" lx={1065} ly={420} />

        {/* Recurrence Loop State Update */}
        <ModuleBox
          x={495}
          y={500}
          w={440}
          h={98}
          title="Recurrence Loop State Update (Cycles 2–32 ▲)"
          subtitle="while (div_cnt < 5'd31)"
          detail="rem_reg <= next_rem (Restored remainder or trial subtraction result)&#10;quo_reg <= next_quo (Quotient accumulator accumulating bits MSB to LSB)&#10;Feedback loop iterates exactly once per cycle across 32 clock cycles"
          tag="LOOP UPDATE"
        />

        {/* Iteration Counter */}
        <ModuleBox
          x={955}
          y={500}
          w={235}
          h={98}
          title="Iteration Counter"
          subtitle="div_cnt[4:0] (0 → 31)"
          detail="Counts 32 iterations (5-bit)&#10;div_cnt == 31: Combinational&#10;32nd step latch to Stage 3"
          tag="COUNTER"
        />

        <SignalWire d="M642,470 V498" color="ok" label="next_rem" lx={670} ly={482} />
        <SignalWire d="M935,470 V498" color="ok" label="next_quo" lx={965} ly={482} />

        {/* Feedback loop back up to registers */}
        <SignalWire d="M510,500 V95 H493" color="navy" label="32-Cycle Loop Feedback" lx={535} ly={475} width={2.2} dashed flowAnim />

        {/* Timing Clarification Box */}
        <ModuleBox
          x={495}
          y={620}
          w={695}
          h={100}
          title="Hardware Timing: 32 Restoring Iterations (33/34 Total Clocks)"
          subtitle="Verilog RTL Reference: rtl/cpu/core/rv32m_unit.v:L60-120"
          detail="Cycle 1: IDLE→DIV input conditioning &amp; register init (Edge 1 captures abs_op1, abs_op2)&#10;Cycles 2–32: 31 clocked restoring iterations (div_cnt: 0 → 30)&#10;Cycle 33: 32nd combinational step + exception check, result_reg <= final_div_result, moves to DONE&#10;Cycle 34: done=1 asserted, pipeline unfreezes (!stall_pipeline), captures result into EX/WB"
          tag="32 ITERS / 34 CYC"
          isNew
        />

        {/* ════════════════════════════════════════════════════════════════════
            STAGE 3: SIGN CORRECTION, EXCEPTION PRIORITY & HANDSHAKE (CYCLES 33–34)
           ════════════════════════════════════════════════════════════════════ */}
        <SubsystemGroup
          x={1230}
          y={15}
          w={510}
          h={725}
          label="Stage 3 · Sign Correction, Exceptions &amp; Handshake (Cycles 33–34)"
          sub="Two's Complement Correction · RISC-V Exception Priority · Output Latch"
          isNew
        />

        {/* Sign Negators */}
        <g>
          <rect x={1250} y={55} width={115} height={54} rx={3} fill="#ffffff" stroke="#16181d" strokeWidth={1.5} />
          <text x={1307} y={80} textAnchor="middle" style={{ font: '700 12px var(--mono)', fill: 'var(--ink)' }}>- final_quo_u</text>
          <text x={1307} y={97} textAnchor="middle" style={{ font: '500 10px var(--mono)', fill: '#6e727e' }}>Quotient Negator</text>

          <rect x={1250} y={125} width={115} height={54} rx={3} fill="#ffffff" stroke="#16181d" strokeWidth={1.5} />
          <text x={1307} y={150} textAnchor="middle" style={{ font: '700 12px var(--mono)', fill: 'var(--ink)' }}>- final_rem_u</text>
          <text x={1307} y={167} textAnchor="middle" style={{ font: '500 10px var(--mono)', fill: '#6e727e' }}>Remainder Negator</text>
        </g>

        {/* Sign Correction MUXes */}
        <Mux2to1 x={1395} y={55} w={28} h={54} label="MUX" selLabel="neg_quo" />
        <text x={1430} y={73} style={{ font: '500 10px var(--mono)', fill: '#4a4e57' }}>1: -quo_u</text>
        <text x={1430} y={97} style={{ font: '500 10px var(--mono)', fill: '#4a4e57' }}>0: quo_u</text>

        <Mux2to1 x={1395} y={125} w={28} h={54} label="MUX" selLabel="neg_rem" />
        <text x={1430} y={143} style={{ font: '500 10px var(--mono)', fill: '#4a4e57' }}>1: -rem_u</text>
        <text x={1430} y={167} style={{ font: '500 10px var(--mono)', fill: '#4a4e57' }}>0: rem_u</text>

        <SignalWire d="M1365,82 H1393" />
        <SignalWire d="M1365,152 H1393" />

        {/* Sign Selection Note Box */}
        <ModuleBox
          x={1455}
          y={55}
          w={265}
          h={124}
          title="Signed / Unsigned Select"
          subtitle="final_quo &amp; final_rem"
          detail="DIV / REM uses signed corrected outputs&#10;DIVU / REMU bypasses negation directly&#10;Full compliance with RISC-V 2's complement"
          tag="CORRECTION"
        />

        {/* Forward wire from Stage 2 into Stage 3 */}
        <SignalWire d="M1090,430 H1240 V82 H1248" color="navy" label="final_quo_u" lx={1170} ly={240} width={2.2} />

        {/* RISC-V Priority Exception Multiplexer */}
        <ModuleBox
          x={1250}
          y={205}
          w={470}
          h={255}
          title="RISC-V Priority Exception Multiplexer"
          subtitle="final_div_result[31:0] MUX (Priority Order)"
          detail="1. if (div_zero): [Division by zero rule]&#10;     DIV / DIVU → 32'hFFFF_FFFF (-1 signed / 2^32 - 1 unsigned)&#10;     REM / REMU → orig_op1 (Preserves dividend unaltered)&#10;&#10;2. else if (overflow): [Signed overflow rule: INT_MIN / -1]&#10;     DIV → 32'h8000_0000 (INT_MIN unaltered)&#10;     REM → 32'h0000_0000 (Zero remainder)&#10;&#10;3. else: [Normal Arithmetic]&#10;     DIV → final_quo   |  DIVU → final_quo_u&#10;     REM → final_rem   |  REMU → final_rem_u"
          tag="PRIORITY MUX"
          isNew
        />

        <SignalWire d="M1423,82 H1485 V203" />
        <SignalWire d="M1423,152 H1520 V203" />

        {/* Architectural Result Register */}
        <ModuleBox
          x={1250}
          y={485}
          w={470}
          h={105}
          title="Architectural Result Register (Cycle 33 ▲)"
          subtitle="result_reg[31:0] <= final_div_result"
          detail="Latched on Clock 33 ▲ (div_cnt == 31) when moving to STATE_DONE&#10;Held stable throughout pipeline acceptance&#10;Directly drives output result[31:0] into EX Stage ex_result MUX"
          tag="RESULT REG"
          isNew
        />

        <SignalWire d="M1485,460 V483" color="navy" label="final_div_result[31:0]" lx={1485} ly={472} width={2.4} />

        {/* Pipeline Handshake & Done Strobe */}
        <ModuleBox
          x={1250}
          y={615}
          w={470}
          h={105}
          title="Pipeline Handshake &amp; Stall Release (Cycle 34)"
          subtitle="Handshake Status Signals"
          detail="done = 1'b1 · busy = 1'b0 (Released)&#10;Deasserts m_stalling → stall_pipeline = 0&#10;CPU pipeline captures result_reg into EX/WB register on posedge clk&#10;Unit returns to STATE_IDLE when !stall_pipeline"
          tag="HANDSHAKE"
          isNew
        />

        <SignalWire d="M1485,590 V613" color="ok" label="done strobe" lx={1485} ly={602} width={2.2} />
      </svg>
    </div>
  )
}
