import { DiagramDefs, ModuleBox, Mux2to1, SignalWire, SubsystemGroup } from '../components/Primitives'

export default function Slide3_Multiplier() {
  return (
    <div style={{ position: 'relative', width: 1760, height: 860, margin: '20px auto 0' }}>
      <svg className="svg-canvas" width="1760" height="740" viewBox="0 0 1760 740">
        <DiagramDefs />

        {/* ════════════════════════════════════════════════════════════════════
            CYCLE 1: OPERAND CONDITIONING & SIGN EXTENSION (CYCLE 1)
           ════════════════════════════════════════════════════════════════════ */}
        <SubsystemGroup
          x={20}
          y={20}
          w={390}
          h={680}
          label="Cycle 1 · Operand Conditioning &amp; Sign Extension"
          sub="33-bit Signed / Unsigned Extension based on funct3"
          isNew
        />

        {/* Inputs */}
        <ModuleBox x={40} y={60} w={150} h={64} title="Operand 1" subtitle="op1[31:0] (rs1)" detail="From EX Forwarding MUX" tag="32-BIT" />
        <ModuleBox x={40} y={150} w={150} h={64} title="Operand 2" subtitle="op2[31:0] (rs2)" detail="From EX Forwarding MUX" tag="32-BIT" />
        <ModuleBox x={40} y={240} w={150} h={64} title="Funct3" subtitle="funct3[2:0]" detail="Operation Encoding" tag="3-BIT" />

        {/* Sign Decode Logic */}
        <ModuleBox
          x={40}
          y={340}
          w={350}
          h={110}
          title="Sign Detection Decoder"
          subtitle="Signed vs Unsigned Logic"
          detail="sign_a = (funct3 == F3_MULH) || (funct3 == F3_MULHSU)&#10;sign_b = (funct3 == F3_MULH)&#10;Controls bit 32 sign-extension"
          tag="COMBINATIONAL"
        />

        {/* Sign Extension MUX A */}
        <Mux2to1 x={240} y={65} w={28} h={70} label="MUX" selLabel="sign_a" />
        <text x={275} y={85} style={{ font: '500 11px var(--mono)', fill: '#4a4e57' }}>0: {`{1'b0, op1}`}</text>
        <text x={275} y={115} style={{ font: '500 11px var(--mono)', fill: '#4a4e57' }}>1: {`{op1[31], op1}`}</text>

        {/* Sign Extension MUX B */}
        <Mux2to1 x={240} y={155} w={28} h={70} label="MUX" selLabel="sign_b" />
        <text x={275} y={175} style={{ font: '500 11px var(--mono)', fill: '#4a4e57' }}>0: {`{1'b0, op2}`}</text>
        <text x={275} y={205} style={{ font: '500 11px var(--mono)', fill: '#4a4e57' }}>1: {`{op2[31], op2}`}</text>

        {/* Stage 1 Pipeline Registers */}
        <ModuleBox
          x={40}
          y={480}
          w={350}
          h={190}
          title="Stage 1 Pipeline Registers (Clock 1 ▲)"
          subtitle="Latched on (start &amp;&amp; !funct3[2])"
          detail="mult_reg_a[32:0]  <= $signed(ext_a)&#10;mult_reg_b[32:0]  <= $signed(ext_b)&#10;mult_op_r1[2:0]   <= funct3&#10;mult_cnt[1:0]     <= 2'd0&#10;Initiates multi-cycle pipeline stall"
          isNew
          tag="REGISTERS"
        />

        <SignalWire d="M190,92 H238" label="op1[31:0]" lx={214} ly={80} />
        <SignalWire d="M190,182 H238" label="op2[31:0]" lx={214} ly={170} />
        <SignalWire d="M115,304 V338" />
        <SignalWire d="M254,135 V478" label="ext_a[32:0]" lx={254} ly={460} width={2.2} />
        <SignalWire d="M254,225 V478" label="ext_b[32:0]" lx={254} ly={240} width={2.2} />

        {/* ════════════════════════════════════════════════════════════════════
            CYCLE 2: 33×33 PARTIAL PRODUCT MULTIPLICATION (CYCLE 2)
           ════════════════════════════════════════════════════════════════════ */}
        <SubsystemGroup
          x={430}
          y={20}
          w={450}
          h={680}
          label="Cycle 2 · 33×33 Multiplier Array"
          sub="DSP48E1 Slice / Booth-Wallace Partial Product Generation"
          isNew
        />

        <ModuleBox
          x={450}
          y={60}
          w={410}
          h={180}
          title="33-bit × 33-bit Signed Multiplier Array"
          subtitle="Dedicated Hardware DSP48E1 / Logic Multiplier"
          detail="Inputs: mult_reg_a[32:0] × mult_reg_b[32:0]&#10;Signed multiplication yielding 66-bit signed result&#10;Decomposed into partial products:&#10;PP0[49:0] = reg_a[16:0] × reg_b[16:0]&#10;PP1[49:0] = reg_a[32:17] × reg_b[16:0]&#10;PP2[49:0] = reg_a[16:0] × reg_b[32:17]"
          isNew
          tag="MULTIPLIER"
        />

        {/* Multiplier Partial Product Slice Registers */}
        <ModuleBox
          x={450}
          y={270}
          w={410}
          h={160}
          title="Partial Product Accumulator (Clock 2 ▲)"
          subtitle="mult_cnt == 0"
          detail="Pipelined intermediate partial product registers&#10;mult_prod_r2[65:0] <= mult_reg_a * mult_reg_b&#10;mult_op_r2[2:0]   <= mult_op_r1&#10;mult_cnt          <= 2'd1&#10;Preserves critical path slack (+0.420 ns @ 100 MHz)"
          isNew
          tag="CYCLE 2 REG"
        />

        <ModuleBox
          x={450}
          y={460}
          w={410}
          h={210}
          title="Multiplier Cycle Counter &amp; Control"
          subtitle="mult_cnt[1:0] FSM-Free Sequencer"
          detail="mult_cnt == 0: Capture 66-bit product&#10;mult_cnt == 1: Latch result into result_reg&#10;mult_cnt == 2: Assert done strobe&#10;busy = (state == STATE_MULT)&#10;Generates m_stalling to freeze IF and EX stages"
          tag="TIMING LOGIC"
        />

        <SignalWire d="M390,540 H448" color="navy" label="reg_a, reg_b [32:0]" lx={420} ly={526} width={2.4} />
        <SignalWire d="M655,240 V268" color="navy" label="66-bit partial sum" lx={655} ly={254} width={2.4} />

        {/* ════════════════════════════════════════════════════════════════════
            CYCLE 3: 66-BIT PRODUCT LATCH & RESULT SELECTION (CYCLE 3)
           ════════════════════════════════════════════════════════════════════ */}
        <SubsystemGroup
          x={900}
          y={20}
          w={430}
          h={680}
          label="Cycle 3 · 66-Bit Product Latch &amp; Result Slicing"
          sub="Upper 32b vs Lower 32b Extraction based on mult_op_r2"
          isNew
        />

        <ModuleBox
          x={920}
          y={60}
          w={390}
          h={120}
          title="66-Bit Product Register"
          subtitle="mult_prod_r2[65:0]"
          detail="Bit [65]: Product sign bit&#10;Bits [63:32]: Upper 32-bit product (High)&#10;Bits [31:0]: Lower 32-bit product (Low)"
          isNew
          tag="66-BIT REG"
        />

        {/* Bit Splitter */}
        <g>
          <rect x={920} y={210} width={180} height={70} rx={3} fill="#ffffff" stroke="#16181d" strokeWidth={1.5} />
          <text x={1010} y={235} textAnchor="middle" style={{ font: '700 14px var(--mono)', fill: 'var(--ink)' }}>Product Lower</text>
          <text x={1010} y={258} textAnchor="middle" style={{ font: '500 12px var(--mono)', fill: 'var(--navy)' }}>mult_prod_r2[31:0]</text>

          <rect x={1130} y={210} width={180} height={70} rx={3} fill="#ffffff" stroke="#16181d" strokeWidth={1.5} />
          <text x={1220} y={235} textAnchor="middle" style={{ font: '700 14px var(--mono)', fill: 'var(--ink)' }}>Product Upper</text>
          <text x={1220} y={258} textAnchor="middle" style={{ font: '500 12px var(--mono)', fill: 'var(--navy)' }}>mult_prod_r2[63:32]</text>
        </g>

        {/* Result Formatting Multiplexer */}
        <Mux2to1 x={1080} y={320} w={36} h={100} label="MUX" selLabel="is_mul" />
        <text x={1130} y={345} style={{ font: '600 12px var(--mono)', fill: 'var(--navy)' }}>0: [63:32] (MULH*)</text>
        <text x={1130} y={395} style={{ font: '600 12px var(--mono)', fill: 'var(--navy)' }}>1: [31:0] (MUL)</text>

        {/* Selection Decode */}
        <ModuleBox
          x={920}
          y={460}
          w={390}
          h={210}
          title="Operation Formatter Selector"
          subtitle="mult_op_r2 Encoding (Clock 3 ▲)"
          detail="F3_MUL    (3'b000) → mult_prod_r2[31:0]&#10;F3_MULH   (3'b001) → mult_prod_r2[63:32]&#10;F3_MULHSU (3'b010) → mult_prod_r2[63:32]&#10;F3_MULHU  (3'b011) → mult_prod_r2[63:32]&#10;&#10;asserts is_mul = (mult_op_r2 == F3_MUL)&#10;Presents formatted 32-bit word to Output Reg"
          tag="SELECTOR"
        />

        <SignalWire d="M860,350 H918" color="navy" label="mult_prod_r2[65:0]" lx={890} ly={336} width={2.4} />
        <SignalWire d="M1010,180 V208" />
        <SignalWire d="M1220,180 V208" />
        <SignalWire d="M1010,280 V385 H1078" />
        <SignalWire d="M1220,280 V345 H1116" />

        {/* ════════════════════════════════════════════════════════════════════
            CYCLE 4: OUTPUT REGISTER & WRITEBACK HANDSHAKE (CYCLE 4)
           ════════════════════════════════════════════════════════════════════ */}
        <SubsystemGroup
          x={1350}
          y={20}
          w={390}
          h={680}
          label="Cycle 4 · Architectural Result Latch &amp; Done Handshake"
          sub="Clock 4 ▲ · Held until accepted by CPU Pipeline"
          isNew
        />

        {/* Architectural Result Register */}
        <ModuleBox
          x={1370}
          y={100}
          w={350}
          h={150}
          title="Architectural Result Register"
          subtitle="result_reg[31:0] (Clock 4 ▲)"
          detail="Captures output of Formatting MUX&#10;result_reg <= (is_mul) ? prod[31:0] : prod[63:32]&#10;Held stable during pipeline acceptance&#10;Connects directly to EX Stage ex_result MUX"
          isNew
          tag="FINAL REG"
        />

        {/* Handshake Signals */}
        <ModuleBox
          x={1370}
          y={290}
          w={350}
          h={180}
          title="Pipeline Handshake &amp; Stall Release"
          subtitle="Handshake Ports"
          detail="done = 1'b1 (Asserted on Cycle 4)&#10;busy = 1'b0 (Released)&#10;m_stalling deasserts → stall_pipeline = 0&#10;CPU pipeline captures result_reg into EX/WB register&#10;Unit returns to IDLE state"
          isNew
          tag="HANDSHAKE"
        />

        {/* Verilog Code Mapping Card */}
        <ModuleBox
          x={1370}
          y={500}
          w={350}
          h={170}
          title="Verilog RTL Correspondence"
          subtitle="rtl/cpu/core/rv32m_unit.v"
          detail="Lines 42–46: ext_a, ext_b sign-ext MUXes&#10;Lines 49–51: mult_reg_a, mult_reg_b latches&#10;Line 176: mult_prod_r2 <= reg_a * reg_b&#10;Line 181: result_reg <= is_mul ? [31:0] : [63:32]&#10;Line 210: assign result = result_reg"
          tag="VERILOG CODE"
        />

        <SignalWire d="M1116,370 H1368" color="navy" label="formatted[31:0]" lx={1240} ly={356} width={2.4} />
        <SignalWire d="M1545,250 V288" color="ok" label="done = 1'b1" lx={1545} ly={270} width={2.2} />
      </svg>
    </div>
  )
}
