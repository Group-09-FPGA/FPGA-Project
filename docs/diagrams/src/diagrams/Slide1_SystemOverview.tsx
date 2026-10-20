import { DiagramDefs, HeavyBus, ModuleBox, SignalWire, SubsystemGroup } from '../components/Primitives'

export default function Slide1_SystemOverview() {
  return (
    <div style={{ position: 'relative', width: 1760, height: 860, margin: '20px auto 0' }}>
      <svg className="svg-canvas" width="1760" height="740" viewBox="0 0 1760 740">
        <DiagramDefs />

        {/* ════════════════════════════════════════════════════════════════════
            1. TOP: 50 MHz ETHERNET INGESTION DOMAIN (CLK_ETH)
           ════════════════════════════════════════════════════════════════════ */}
        <SubsystemGroup
          x={20}
          y={20}
          w={1720}
          h={140}
          label="1. Network Ingestion Subsystem · clk_eth (50.0 MHz)"
          sub="RMII PHY → Dual-Bank Packet Buffer → IPv4/UDP → MoldUDP64 → ITCH 5.0"
          isNew
        />

        <ModuleBox x={40}  y={50} w={150} h={86} title="LAN8720A" subtitle="RMII PHY (ext)" detail="50 MHz REF_CLK" tag="EXT" />
        <ModuleBox x={230} y={50} w={190} h={86} title="RMII RX / MAC" subtitle="rmii_rx.sv" detail="FCS CRC32 · SFD strip" isNew tag="RTL" />
        <ModuleBox x={460} y={50} w={200} h={86} title="Packet RAM" subtitle="2× 2-KiB Ping-Pong" detail="Bank ownership tokens" isNew tag="2 BRAM" />
        <ModuleBox x={700} y={50} w={210} h={86} title="IPv4 / UDP Parser" subtitle="net_parser.sv" detail="DIX-II · Port/IP filter" isNew tag="RTL" />
        <ModuleBox x={950} y={50} w={220} h={86} title="MoldUDP64 Decoder" subtitle="moldudp64_decoder.sv" detail="Sequence gap/dup check" isNew tag="RTL" />
        <ModuleBox x={1210} y={50} w={220} h={86} title="ITCH 5.0 Parser" subtitle="itch_decoder.sv" detail="A, F, E, C, X, D, U msgs" isNew tag="RTL" />

        {/* Stream arrows */}
        <SignalWire d="M190,93 H228" label="RXD[1:0]" lx={210} ly={80} />
        <SignalWire d="M420,93 H458" label="rx_byte[7:0]" lx={440} ly={80} />
        <SignalWire d="M660,93 H698" label="bank_ok" lx={680} ly={80} />
        <SignalWire d="M910,93 H948" label="payload" lx={930} ly={80} />
        <SignalWire d="M1170,93 H1208" label="itch_bytes" lx={1190} ly={80} />

        {/* ════════════════════════════════════════════════════════════════════
            2. CLOCK DOMAIN CROSSING (CDC) ASYNC EVENT FIFO
           ════════════════════════════════════════════════════════════════════ */}
        <ModuleBox
          x={1470}
          y={40}
          w={250}
          h={106}
          title="Async Event FIFO"
          subtitle="async_event_fifo.sv"
          detail="512× 128b · Gray Pointers · 50M → 100M"
          isNew
          tag="2 BRAM"
        />
        <SignalWire d="M1430,93 H1468" color="navy" label="event[127:0]" lx={1450} ly={80} width={2.4} />

        {/* CDC Wire dropping to 100 MHz LOB core */}
        <SignalWire
          d="M1595,146 V210"
          color="navy"
          label="CDC Crossing: 50 MHz → 100 MHz"
          lx={1595}
          ly={180}
          width={2.4}
          dashed
          flowAnim
        />

        {/* ════════════════════════════════════════════════════════════════════
            3. MIDDLE: 100 MHz CORE DOMAIN (CPU + SYSTEM BUS + LOB)
           ════════════════════════════════════════════════════════════════════ */}
        <SubsystemGroup
          x={20}
          y={190}
          w={1720}
          h={530}
          label="2. Core Processing Subsystem · clk_core (100.0 MHz)"
          sub="3-Stage RV32IM CPU · 32-bit Memory-Mapped Bus · Pure-Hardware Limit Order Book Accelerator"
        />

        {/* ── CPU Core Box ─────────────────────────────────────────────── */}
        <SubsystemGroup
          x={40}
          y={220}
          w={680}
          h={260}
          label="RV32IM CPU Core (cpu_core.v)"
          sub="3-Stage Pipeline: IF | EX | WB"
        />

        <ModuleBox x={60} y={260} w={150} h={100} title="Fetch (IF)" subtitle="fetch_pc, PC+4" detail="1-word skid buffer" tag="STAGE 1" />
        <ModuleBox x={240} y={260} w={190} h={100} title="Execute (EX)" subtitle="ALU + Branch Unit" detail="Forwarding & Regfile" tag="STAGE 2" />
        <ModuleBox x={460} y={260} w={150} h={100} title="Writeback" subtitle="Align LB/LH/LW" detail="SB/SH/SW byte strobe" tag="STAGE 3" />
        <ModuleBox x={630} y={260} w={75} h={200} title="Hazard" subtitle="hazard_unit" detail="2-cy branch stall" tag="RTL" />

        {/* RV32M Unit inside EX */}
        <ModuleBox
          x={240}
          y={380}
          w={370}
          h={80}
          title="RV32M Multiplier / Divider (rv32m_unit.v)"
          subtitle="3-Stage Pipelined MUL (3 cycles)  ·  32-Iteration Restoring DIV (33 cycles)"
          detail="Full RV32M: MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU"
          isNew
          tag="★ EXTENSION"
        />

        {/* Pipeline connection wires */}
        <SignalWire d="M210,310 H238" label="inst[31:0]" lx={225} ly={296} />
        <SignalWire d="M430,310 H458" label="ex_res[31:0]" lx={445} ly={296} />
        <SignalWire d="M335,360 V378" color="navy" label="start / funct3" lx={335} ly={370} />
        <SignalWire d="M630,360 H612" color="warn" label="stall_pipeline" lx={620} ly={350} dashed />

        {/* ── Clock & Reset Manager ────────────────────────────────────── */}
        <ModuleBox
          x={40}
          y={495}
          w={220}
          h={75}
          title="Clock & Reset Mgr"
          subtitle="clk_rst_mgr.sv"
          detail="MMCM: 100M / 50M / 25.175M"
          isNew
          tag="RTL"
        />

        {/* ── System Bus (Heavy bar) ──────────────────────────────────── */}
        <HeavyBus x1={290} y1={530} x2={1430} y2={530} label="SYSTEM BUS (sys_bus_interconnect.v) · 32-bit Pipelined Memory Bus" />

        {/* CPU master connection to bus */}
        <SignalWire d="M535,360 V525" color="ink" label="bus_req: addr[31:0], wdata[31:0], wstrb[3:0]" lx={535} ly={490} width={2.2} />

        {/* Memory Slaves attached to bus */}
        <ModuleBox x={300} y={570} w={150} h={86} title="IMEM (ROM)" subtitle="memory.v" detail="0x0000_0000 · 4 KB BRAM" tag="BRAM" />
        <ModuleBox x={480} y={570} w={150} h={86} title="DMEM (RAM)" subtitle="memory.v" detail="0x2000_0000 · 4 KB BRAM" tag="BRAM" />
        <ModuleBox x={660} y={570} w={170} h={86} title="7-Seg / LEDs" subtitle="top_fpga.v" detail="0x3000_0000 · Board I/O" tag="GPIO" />
        <ModuleBox
          x={860}
          y={570}
          w={250}
          h={86}
          title="LOB MMIO Slave"
          subtitle="lob_mmio_slave.sv"
          detail="0x4000_0000 · BBO Shadow + Status"
          isNew
          tag="MMIO SLAVE"
        />

        {/* Bus taps */}
        <SignalWire d="M375,533 V568" label="0x0000" lx={375} ly={550} />
        <SignalWire d="M555,533 V568" label="0x2000" lx={555} ly={550} />
        <SignalWire d="M745,533 V568" label="0x3000" lx={745} ly={550} />
        <SignalWire d="M985,533 V568" color="navy" label="0x4000" lx={985} ly={550} width={2.2} />

        {/* ── Pure-Hardware Limit Order Book Core ─────────────────────── */}
        <SubsystemGroup
          x={750}
          y={220}
          w={970}
          h={300}
          label="Pure-Hardware Limit Order Book Core (lob_core.sv)"
          sub="Deterministic Op Sequencer · Single-Cycle RAM Latency · Zero CPU Involvement in Hot Path"
          isNew
        />

        <ModuleBox
          x={770}
          y={255}
          w={200}
          h={70}
          title="Event Decoder"
          subtitle="lob_event_decoder.sv"
          detail="128b → Op, ID, Px, Qty"
          isNew
          tag="RTL"
        />

        <ModuleBox
          x={1000}
          y={255}
          w={310}
          h={70}
          title="Op Sequencer FSM"
          subtitle="Add (10cy) · Exec/Cancel (8cy) · Del (8cy)"
          detail="Deterministic Cycle Schedules · Fail-Stop"
          isNew
          tag="SEQUENCER"
        />

        <ModuleBox
          x={1340}
          y={255}
          w={210}
          h={70}
          title="Priority BBO Engine"
          subtitle="lob_bbo.sv"
          detail="Best Bid / Best Ask Search"
          isNew
          tag="BBO ENGINE"
        />

        <ModuleBox
          x={1570}
          y={255}
          w={130}
          h={70}
          title="Shadow Regs"
          subtitle="BBO Snapshots"
          detail="1-cy Latch"
          isNew
          tag="COHERENT"
        />

        {/* LOB RAM Structures (Row 2 inside LOB) */}
        <ModuleBox x={770} y={350} w={180} h={75} title="CRC32-C Hash" subtitle="lob_hash_table.sv" detail="2048-Set × 4-Way" isNew tag="24 BRAM" />
        <ModuleBox x={970} y={350} w={130} h={75} title="Stash CAM" subtitle="16-Entry CAM" detail="Overflow Ways" isNew tag="LUTRAM" />
        <ModuleBox x={1120} y={350} w={180} h={75} title="Slot Table" subtitle="lob_slot_table.sv" detail="4096 × 129b Orders" isNew tag="15 BRAM" />
        <ModuleBox x={1320} y={350} w={180} h={75} title="Free-List FIFO" subtitle="lob_free_list.sv" detail="4096-Depth Indices" isNew tag="FIFO" />
        <ModuleBox x={1520} y={350} w={180} h={75} title="Price Level RAM" subtitle="lob_price_ram.sv" detail="65,536 × 32b Dual-Port" isNew tag="64 BRAM" />

        <ModuleBox x={1120} y={440} w={380} h={65} title="Occupancy Mask Hierarchy (lob_occupancy.sv)" subtitle="L0: 32b Reg  ·  L1: 32×32b LUTRAM  ·  L2: 1K×32b BRAM per side" detail="Instant zero-quantity detection for BBO Priority Encoder" isNew tag="2 BRAM" />

        {/* Wires inside LOB */}
        <SignalWire d="M970,290 H998" color="navy" label="canonical_event" lx={985} ly={276} />
        <SignalWire d="M1310,290 H1338" color="navy" label="occ_mask" lx={1325} ly={276} />
        <SignalWire d="M1550,290 H1568" color="navy" label="bbo_live" lx={1560} ly={276} />
        <SignalWire d="M1635,325 V565 H1112" color="navy" label="BBO Snapshot to MMIO" lx={1635} ly={470} width={2.2} />

        {/* ════════════════════════════════════════════════════════════════════
            4. DISPLAY SUBSYSTEM (CLK_VGA 25.175 MHz)
           ════════════════════════════════════════════════════════════════════ */}
        <ModuleBox
          x={1160}
          y={570}
          w={220}
          h={86}
          title="VGA Framebuffer"
          subtitle="640×480 Monochrome"
          detail="307,200 bits · Port A: Core / Port B: VGA"
          tag="9 BRAM"
        />
        <ModuleBox
          x={1410}
          y={570}
          w={170}
          h={86}
          title="VGA Controller"
          subtitle="clk_vga (25.175 MHz)"
          detail="H/V Sync Generator"
          tag="TIMING"
        />
        <ModuleBox
          x={1610}
          y={570}
          w={110}
          h={86}
          title="VGA DAC"
          subtitle="4-bit R/G/B"
          detail="Resistors"
          tag="EXT"
        />

        <SignalWire d="M1380,613 H1408" label="pixel_data" lx={1395} ly={600} />
        <SignalWire d="M1580,613 H1608" label="RGB / Sync" lx={1595} ly={600} />
      </svg>

      {/* ── Clean 3-Card Summary at Bottom ── */}
      <div style={{ position: 'absolute', left: 20, right: 20, bottom: 20, display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 32 }}>
        <div style={{ background: '#ffffff', border: '1.5px solid var(--line)', padding: '16px 20px', borderRadius: 4 }}>
          <div style={{ font: '700 13px var(--mono)', color: 'var(--navy)', letterSpacing: '.08em', textTransform: 'uppercase' }}>
            System Partitioning
          </div>
          <p style={{ font: '400 15px/1.4 var(--font)', color: 'var(--ink-2)', marginTop: 4 }}>
            <b>3 Independent Clock Domains:</b> 50 MHz RMII network ingestion, 100 MHz CPU core &amp; hardware order book accelerator, and 25.175 MHz VGA display generator.
          </p>
        </div>

        <div style={{ background: '#ffffff', border: '1.5px solid var(--navy)', padding: '16px 20px', borderRadius: 4 }}>
          <div style={{ font: '700 13px var(--mono)', color: 'var(--navy)', letterSpacing: '.08em', textTransform: 'uppercase' }}>
            Pure-Hardware Accelerator
          </div>
          <p style={{ font: '400 15px/1.4 var(--font)', color: 'var(--ink-2)', marginTop: 4 }}>
            <b>Deterministic 10-Cycle Processing:</b> Order Book operations execute directly across 107 dedicated BRAMs with zero CPU latency or bus contention.
          </p>
        </div>

        <div style={{ background: '#ffffff', border: '1.5px solid var(--line)', padding: '16px 20px', borderRadius: 4 }}>
          <div style={{ font: '700 13px var(--mono)', color: 'var(--navy)', letterSpacing: '.08em', textTransform: 'uppercase' }}>
            CPU Supervision &amp; MMIO
          </div>
          <p style={{ font: '400 15px/1.4 var(--font)', color: 'var(--ink-2)', marginTop: 4 }}>
            <b>Non-Intrusive Monitoring:</b> The RV32IM softcore reads coherent BBO snapshots from shadow registers at <code>0x4000_0000</code> without stalling matching ingestion.
          </p>
        </div>
      </div>
    </div>
  )
}
