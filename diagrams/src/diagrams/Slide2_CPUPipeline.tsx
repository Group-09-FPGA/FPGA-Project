import { DiagramDefs, ModuleBox, Mux2to1, PipelineReg, SignalWire, SubsystemGroup } from '../components/Primitives'

export default function Slide2_CPUPipeline() {
  return (
    <div style={{ position: 'relative', width: 1760, height: 860, margin: '20px auto 0' }}>
      <svg className="svg-canvas" width="1760" height="740" viewBox="0 0 1760 740">
        <DiagramDefs />

        {/* ════════════════════════════════════════════════════════════════════
            STAGE 1: INSTRUCTION FETCH (IF)
           ════════════════════════════════════════════════════════════════════ */}
        <SubsystemGroup x={20} y={30} w={360} h={640} label="IF · Instruction Fetch" sub="PC Logic · IMEM · Skid Buffer" />

        {/* PC MUX */}
        <Mux2to1 x={40} y={130} w={28} h={80} label="MUX" selLabel="PCSrc" />
        <text x={34} y={150} style={{ font: '600 11px var(--mono)', fill: '#6e727e' }}>0</text>
        <text x={34} y={190} style={{ font: '600 11px var(--mono)', fill: '#6e727e' }}>1</text>

        {/* PC Register */}
        <ModuleBox x={95} y={130} w={115} h={80} title="PC" subtitle="fetch_pc[31:0]" detail="Clocked Reg" tag="32-BIT" />

        {/* PC + 4 Adder */}
        <ModuleBox x={100} y={48} w={90} h={52} title="ADD 4" subtitle="PC + 4" detail="Sequential" tag="ADD" />

        {/* IMEM */}
        <ModuleBox x={235} y={120} w={130} h={100} title="IMEM (ROM)" subtitle="memory.v" detail="4 KB Sync BRAM" tag="BRAM" />

        {/* 1-Word Skid Buffer */}
        <ModuleBox x={235} y={240} w={130} h={70} title="Skid Buffer" subtitle="if_buf[31:0]" detail="Holds word on stall" tag="REG" />

        {/* Instruction Select MUX */}
        <Mux2to1 x={330} y={330} w={24} h={60} label="MUX" selLabel="stall" />

        {/* Wires in IF stage */}
        <SignalWire d="M68,170 H93" label="next_pc" lx={80} ly={158} width={2.2} />
        <SignalWire d="M210,170 H233" label="fetch_pc[31:0]" lx={222} ly={158} width={2.2} />
        <SignalWire d="M152,130 V102" />
        <SignalWire d="M152,48 V38 H25 V145 H38" label="PC + 4" lx={80} ly={34} />
        <SignalWire d="M300,220 V238" />
        <SignalWire d="M300,310 V345 H328" />

        {/* Bus Master Arbiter in IF */}
        <ModuleBox
          x={40}
          y={440}
          w={320}
          h={110}
          title="Bus Master Arbiter (cpu_core.v)"
          subtitle="Priority: WB Store > EX Load > IF Fetch"
          detail="States: IDLE · WAIT_IF · WAIT_EX · WAIT_WB"
          tag="ARBITER"
        />

        <SignalWire d="M150,210 V438" label="bus_req_addr = fetch_pc" lx={150} ly={420} />

        {/* ════════════════════════════════════════════════════════════════════
            PIPELINE REGISTER 1: IF / ID
           ════════════════════════════════════════════════════════════════════ */}
        <PipelineReg x={400} y={40} w={26} h={620} label="IF / ID" sub="LATCH" />
        <SignalWire d="M354,360 H398" label="inst[31:0]" lx={376} ly={348} width={2.2} />

        {/* ════════════════════════════════════════════════════════════════════
            STAGE 2: INSTRUCTION DECODE (ID)
           ════════════════════════════════════════════════════════════════════ */}
        <SubsystemGroup x={440} y={30} w={350} h={640} label="ID · Instruction Decode" sub="decoder.v · Control Logic" />

        {/* Instruction Decoder */}
        <ModuleBox
          x={460}
          y={80}
          w={310}
          h={130}
          title="Decoder (decoder.v)"
          subtitle="Opcode[6:0] · Funct3[2:0] · Funct7[6:0]"
          detail="Extracts rs1[4:0], rs2[4:0], rd[4:0], imm[31:0]"
          tag="DECODER"
        />

        {/* Control Signals Unit */}
        <ModuleBox
          x={460}
          y={230}
          w={310}
          h={180}
          title="Main Control Generator"
          subtitle="Decodes 12 Primary Control Signals:"
          detail="RegWrite · MemWrite · MemToReg · Branch · ALUOp[2:0] · ALUSrc · ArithSubType · is_m_op · JAL · JALR · LUI · AUIPC"
          tag="CONTROL"
        />

        {/* Immediate Generator */}
        <ModuleBox
          x={460}
          y={430}
          w={310}
          h={90}
          title="Immediate Generator"
          subtitle="Sign-Extension Unit"
          detail="I, S, B, U, J Formats → 32-bit immediate"
          tag="SIGN-EXT"
        />

        {/* Illegal Instruction Trap */}
        <ModuleBox
          x={460}
          y={540}
          w={310}
          h={70}
          title="Exception Unit"
          subtitle="illegal_inst || misaligned_pc"
          detail="Sets exception register on invalid opcodes"
          tag="TRAP"
        />

        {/* ════════════════════════════════════════════════════════════════════
            PIPELINE REGISTER 2: ID / EX
           ════════════════════════════════════════════════════════════════════ */}
        <PipelineReg x={810} y={40} w={26} h={620} label="ID / EX" sub="LATCH" />

        <SignalWire d="M770,140 H808" label="rs1, rs2, rd" lx={790} ly={126} width={2.2} />
        <SignalWire d="M770,320 H808" color="navy" label="Control Bus" lx={790} ly={306} width={2.4} />
        <SignalWire d="M770,475 H808" label="imm[31:0]" lx={790} ly={461} width={2.2} />

        {/* ════════════════════════════════════════════════════════════════════
            STAGE 3: EXECUTE (EX)
           ════════════════════════════════════════════════════════════════════ */}
        <SubsystemGroup x={855} y={30} w={530} h={640} label="EX · Execution" sub="Regfile · Forwarding · ALU · RV32M Unit" />

        {/* Register File */}
        <ModuleBox
          x={875}
          y={60}
          w={220}
          h={120}
          title="Register File (reg_file.v)"
          subtitle="32 × 32-bit Registers · x0 Hardwired 0"
          detail="Dual Async Read Ports · Sync Write Port"
          tag="REGFILE"
        />

        {/* Forwarding Unit */}
        <ModuleBox
          x={1135}
          y={60}
          w={230}
          h={120}
          title="Forwarding Unit"
          subtitle="forwarding_unit.v"
          detail="Detects RAW Hazards (WB → EX Bypass)"
          tag="FORWARDING"
        />

        {/* Operand Muxes */}
        <Mux2to1 x={970} y={200} w={26} h={54} label="MUX" selLabel="FwdA" />
        <Mux2to1 x={970} y={280} w={26} h={54} label="MUX" selLabel="FwdB" />
        <Mux2to1 x={1030} y={280} w={26} h={54} label="MUX" selLabel="ALUSrc" />

        {/* 32-bit ALU */}
        <ModuleBox
          x={1080}
          y={200}
          w={140}
          h={110}
          title="ALU (alu.v)"
          subtitle="ADD/SUB, SLL, SLT,"
          detail="SLTU, XOR, SRL, SRA, OR, AND"
          tag="32-BIT ALU"
        />

        {/* Branch Unit */}
        <ModuleBox
          x={1245}
          y={200}
          w={120}
          h={110}
          title="Branch Unit"
          subtitle="branch_unit.v"
          detail="BEQ, BNE, BLT, BGE, BLTU, BGEU"
          tag="BRANCH"
        />

        {/* RV32M Accelerator Unit (Highlighted New!) */}
        <ModuleBox
          x={875}
          y={360}
          w={490}
          h={110}
          title="RV32M Multiplier / Divider Accelerator (rv32m_unit.v)"
          subtitle="3-Stage Pipelined Multiplier (3-cycle stall)  ·  32-Iteration Restoring Divider (33-cycle stall)"
          detail="Inputs: op1, op2, funct3[2:0], start  |  Outputs: result[31:0], busy, done  |  FSM: IDLE → MULT/DIV → DONE"
          isNew
          tag="★ EXTENSION"
        />

        {/* Result MUX */}
        <Mux2to1 x={1245} y={500} w={30} h={80} label="MUX" selLabel="ResultSrc" />
        <text x={1285} y={515} style={{ font: '500 12px var(--mono)', fill: '#4a4e57' }}>0: ALU out</text>
        <text x={1285} y={535} style={{ font: '500 12px var(--mono)', fill: 'var(--navy)' }}>1: RV32M res</text>
        <text x={1285} y={555} style={{ font: '500 12px var(--mono)', fill: '#4a4e57' }}>2: Imm / PC+4</text>

        {/* Address Adder for Load/Store */}
        <ModuleBox
          x={875}
          y={500}
          w={220}
          h={60}
          title="Address Generator"
          subtitle="ex_mem_address = op1 + imm"
          detail="Effective address for Load / Store"
          tag="ADDR"
        />

        {/* Wires inside EX */}
        <SignalWire d="M996,227 H1078" label="op1[31:0]" lx={1037} ly={213} />
        <SignalWire d="M1056,307 H1078" label="op2[31:0]" lx={1067} ly={293} />
        <SignalWire d="M1220,255 H1243" label="zero/comp" lx={1232} ly={241} />
        <SignalWire d="M1220,280 V520 H1243" label="alu_out" lx={1220} ly={490} />
        <SignalWire d="M1120,470 V540 H1243" color="navy" label="m_result[31:0]" lx={1170} ly={530} />

        {/* Branch redirect wire back to IF stage */}
        <SignalWire
          d="M1305,200 V18 H70 V190 H38"
          color="warn"
          label="branch_taken (Target = ex_pc + imm)"
          lx={700}
          ly={14}
          width={2.2}
          dashed
        />

        {/* ════════════════════════════════════════════════════════════════════
            PIPELINE REGISTER 3: EX / WB
           ════════════════════════════════════════════════════════════════════ */}
        <PipelineReg x={1405} y={40} w={26} h={620} label="EX / WB" sub="LATCH" />

        <SignalWire d="M1275,540 H1403" label="wb_res[31:0]" lx={1340} ly={526} width={2.2} />
        <SignalWire d="M1095,530 H1403" label="wb_addr[31:0]" lx={1340} ly={600} width={2.2} />

        {/* ════════════════════════════════════════════════════════════════════
            STAGE 4: WRITEBACK & MEMORY (WB)
           ════════════════════════════════════════════════════════════════════ */}
        <SubsystemGroup x={1450} y={30} w={290} h={640} label="WB · Writeback &amp; Memory" sub="Memory Access · Alignment" />

        {/* Load Alignment */}
        <ModuleBox
          x={1470}
          y={80}
          w={250}
          h={100}
          title="Load Alignment Unit"
          subtitle="LB, LBU, LH, LHU, LW"
          detail="Byte/Halfword extraction & sign-ext"
          tag="LOAD"
        />

        {/* Store Alignment */}
        <ModuleBox
          x={1470}
          y={200}
          w={250}
          h={100}
          title="Store Alignment Unit"
          subtitle="SB, SH, SW + wstrb[3:0]"
          detail="Replicates data & creates byte enables"
          tag="STORE"
        />

        {/* Writeback MUX */}
        <Mux2to1 x={1580} y={330} w={30} h={70} label="MUX" selLabel="MemToReg" />
        <text x={1620} y={350} style={{ font: '500 12px var(--mono)', fill: '#4a4e57' }}>0: wb_result</text>
        <text x={1620} y={380} style={{ font: '500 12px var(--mono)', fill: '#4a4e57' }}>1: dmem_rdata</text>

        {/* Hazard Unit Box in WB */}
        <ModuleBox
          x={1470}
          y={440}
          w={250}
          h={120}
          title="Hazard Unit (hazard_unit.v)"
          subtitle="Stall Generation & Branch Bubbles"
          detail="Asserts stall_pipeline when m_stalling, ex_stalling, or 2-cycle branch penalty active"
          tag="HAZARD"
        />

        {/* Forwarding path from WB back to EX */}
        <SignalWire
          d="M1610,365 V420 H1440 V20 H1200 V58"
          color="ok"
          label="WB-to-EX Forwarding Bus (wb_result / wb_read_data)"
          lx={1320}
          ly={14}
          width={2.2}
          dashed
        />

        {/* Writeback to Regfile wire */}
        <SignalWire
          d="M1610,365 H1660 V690 H985 V182"
          color="navy"
          label="Write Data Bus (write_addr = wb_rd, write_data = wb_final)"
          lx={1320}
          ly={680}
          width={2.4}
        />

        {/* Stall signal to all pipeline stages */}
        <SignalWire
          d="M1470,500 H400 V640"
          color="warn"
          label="Global Pipeline Stall (stall_pipeline)"
          lx={935}
          ly={630}
          width={2.2}
          dashed
        />

        {/* Clock and Reset indicators */}
        <g>
          <rect x={20} y={690} width={240} height={32} rx={3} fill="#ffffff" stroke="#16181d" strokeWidth={1.2} />
          <text x={32} y={711} style={{ font: '600 13px var(--mono)', fill: 'var(--ink)' }}>CLK: clk_core (100 MHz)</text>
          <text x={190} y={711} style={{ font: '600 13px var(--mono)', fill: 'var(--warn)' }}>RST: reset_n</text>
        </g>
      </svg>

      {/* ── Summary Notes ── */}
      <div style={{ position: 'absolute', left: 20, right: 20, bottom: 20, display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 32 }}>
        <div style={{ background: '#ffffff', border: '1.5px solid var(--line)', padding: '14px 18px', borderRadius: 4 }}>
          <div style={{ font: '700 13px var(--mono)', color: 'var(--navy)', letterSpacing: '.08em', textTransform: 'uppercase' }}>
            Pipeline Architecture
          </div>
          <p style={{ font: '400 14px/1.4 var(--font)', color: 'var(--ink-2)', marginTop: 4 }}>
            <b>3 Physical Stages:</b> Fetch (IF), Execution with fused decode &amp; regfile (EX), and Writeback (WB) with dedicated <code>IF/ID</code>, <code>ID/EX</code>, and <code>EX/WB</code> registers.
          </p>
        </div>

        <div style={{ background: '#ffffff', border: '1.5px solid var(--navy)', padding: '14px 18px', borderRadius: 4 }}>
          <div style={{ font: '700 13px var(--mono)', color: 'var(--navy)', letterSpacing: '.08em', textTransform: 'uppercase' }}>
            RV32M Multi-Cycle Integration
          </div>
          <p style={{ font: '400 14px/1.4 var(--font)', color: 'var(--ink-2)', marginTop: 4 }}>
            <b>Deterministic Stall Logic:</b> Initiated by single-cycle <code>m_start</code> strobe. Freezes the IF and ID/EX registers via <code>stall_pipeline</code> for 3 cycles (MUL) or 33 cycles (DIV).
          </p>
        </div>

        <div style={{ background: '#ffffff', border: '1.5px solid var(--line)', padding: '14px 18px', borderRadius: 4 }}>
          <div style={{ font: '700 13px var(--mono)', color: 'var(--navy)', letterSpacing: '.08em', textTransform: 'uppercase' }}>
            Hazard Resolution
          </div>
          <p style={{ font: '400 14px/1.4 var(--font)', color: 'var(--ink-2)', marginTop: 4 }}>
            <b>Forwarding &amp; Bubbles:</b> WB-to-EX forwarding avoids stalls on arithmetic dependencies. Taken branches incur a deterministic 2-cycle bubble managed by <code>hazard_unit.v</code>.
          </p>
        </div>
      </div>
    </div>
  )
}
