import { DiagramDefs, ModuleBox, SignalWire, SubsystemGroup } from '../components/Primitives'

export default function Slide4_LOBCore() {
  return (
    <div style={{ position: 'relative', width: 1760, height: 860, margin: '20px auto 0' }}>
      <svg className="svg-canvas" width="1760" height="740" viewBox="0 0 1760 740">
        <DiagramDefs />

        {/* ════════════════════════════════════════════════════════════════════
            TOP: EVENT INGESTION & SEQUENCER ORCHESTRATION
           ════════════════════════════════════════════════════════════════════ */}
        <SubsystemGroup
          x={20}
          y={20}
          w={1720}
          h={150}
          label="1. Ingestion Interface &amp; Op Sequencer FSM (lob_core.sv · 100 MHz)"
          sub="Deterministic Execution · 10-Cycle Add · 8-Cycle Cancel/Delete · Single-Cycle Memory Timing"
          isNew
        />

        <ModuleBox
          x={40}
          y={50}
          w={220}
          h={96}
          title="Async CDC FIFO"
          subtitle="512 × 128-bit Words"
          detail="Dual-Clock Gray Pointers&#10;50 MHz Write / 100 MHz Read"
          isNew
          tag="2 BRAM"
        />

        <ModuleBox
          x={300}
          y={50}
          w={260}
          h={96}
          title="Canonical Event Decoder"
          subtitle="lob_event_decoder.sv"
          detail="Opcode[3:0] · Order_ID[63:0]&#10;Price[31:0] · Shares[27:0]"
          isNew
          tag="DECODER"
        />

        <ModuleBox
          x={600}
          y={50}
          w={450}
          h={96}
          title="Op Sequencer FSM (lob_core.sv)"
          subtitle="One Operation In-Flight · Strict Cycle Schedule"
          detail="States: IDLE · ADD_C0–C9 · EXEC_C0–C7 · CANCEL_C0–C7 · DEL_C0–C7&#10;Atomicity: Replace (U) split into sequential Delete + Add"
          isNew
          tag="SEQUENCER"
        />

        <ModuleBox
          x={1090}
          y={50}
          w={310}
          h={96}
          title="Priority BBO Engine"
          subtitle="lob_bbo.sv"
          detail="Best Bid = Highest set bit in Bid Mask&#10;Best Ask = Lowest set bit in Ask Mask"
          isNew
          tag="BBO ENGINE"
        />

        <ModuleBox
          x={1440}
          y={50}
          w={280}
          h={96}
          title="Coherent Shadow Regs"
          subtitle="lob_mmio_slave.sv (0x4000_0000)"
          detail="1-Cycle Latch on Strobe: Freeze Bid/Ask&#10;Prevents CPU read-tearing during live updates"
          isNew
          tag="MMIO REGS"
        />

        {/* Top flow arrows */}
        <SignalWire d="M260,98 H298" color="navy" label="event[127:0]" lx={279} ly={86} width={2.2} />
        <SignalWire d="M560,98 H598" color="navy" label="decoded_event" lx={579} ly={86} width={2.2} />
        <SignalWire d="M1050,98 H1088" color="navy" label="mask_update" lx={1069} ly={86} width={2.2} />
        <SignalWire d="M1400,98 H1438" color="navy" label="bbo_live" lx={1419} ly={86} width={2.2} />

        {/* ════════════════════════════════════════════════════════════════════
            MIDDLE: THE 6 DEDICATED HARDWARE MEMORY PRIMITIVES (107 BRAMs)
           ════════════════════════════════════════════════════════════════════ */}
        <SubsystemGroup
          x={20}
          y={190}
          w={1720}
          h={250}
          label="2. Hardware Memory Primitives &amp; Storage Layout (107 Total RAMB36E1 BRAMs)"
          sub="No Pointers · No Dynamic Allocation · Fixed-Latency Single-Port / True Dual-Port Access"
          isNew
        />

        {/* Primitive 1: Hash Table */}
        <ModuleBox
          x={40}
          y={230}
          w={260}
          h={120}
          title="Order-ID Hash Table"
          subtitle="lob_hash_table.sv"
          detail="2048 Sets × 4 Ways (8,192 Entries)&#10;CRC32-C(Order_ID)[10:0] Hash Index&#10;Port A: R/W @ 100 MHz"
          isNew
          tag="24 BRAM"
        />

        {/* Primitive 2: Stash CAM */}
        <ModuleBox
          x={330}
          y={230}
          w={220}
          h={120}
          title="Collision Stash (CAM)"
          subtitle="Distributed LUTRAM"
          detail="16-Entry Fully-Associative CAM&#10;Catches 4-Way Set Overflows&#10;Full Stash → Assert Fail-Stop"
          isNew
          tag="LUTRAM"
        />

        {/* Primitive 3: Slot Table */}
        <ModuleBox
          x={580}
          y={230}
          w={270}
          h={120}
          title="Order Slot RAM"
          subtitle="lob_slot_table.sv"
          detail="4096 Entries × 129 Bits&#10;Fields: {Valid, Side, ID, Price, Qty}&#10;Indexed directly by Slot_ID[11:0]"
          isNew
          tag="15 BRAM"
        />

        {/* Primitive 4: Free-List FIFO */}
        <ModuleBox
          x={880}
          y={230}
          w={240}
          h={120}
          title="Free-List FIFO"
          subtitle="lob_free_list.sv"
          detail="4096-Depth Index FIFO&#10;Pop on Add → Assign Slot_ID&#10;Push on Delete → Recycle Slot_ID"
          isNew
          tag="FIFO"
        />

        {/* Primitive 5: Price Level RAM */}
        <ModuleBox
          x={1150}
          y={230}
          w={280}
          h={120}
          title="Price Level RAM"
          subtitle="lob_price_ram.sv"
          detail="65,536 Price Levels × 32 Bits&#10;Addr = {Side[0], Price_Index[14:0]}&#10;Port A: Read  |  Port B: Write"
          isNew
          tag="64 BRAM"
        />

        {/* Primitive 6: Occupancy Mask */}
        <ModuleBox
          x={1460}
          y={230}
          w={260}
          h={120}
          title="Occupancy Hierarchy"
          subtitle="lob_occupancy.sv"
          detail="L0: 32-bit Register&#10;L1: 32 × 32-bit LUTRAM&#10;L2: 1024 × 32-bit BRAM per side"
          isNew
          tag="2 BRAM"
        />

        {/* Sequencer Bus down to all RAMs */}
        <line x1={825} y1={146} x2={825} y2={185} stroke="var(--navy)" strokeWidth={2.4} />
        <SignalWire d="M825,185 V225 H170 V230" color="navy" label="Read/Write Strobes" lx={450} ly={180} />
        <SignalWire d="M825,185 V225 H1290 V230" color="navy" label="Dual-Port RAM Sched" lx={1100} ly={180} />

        {/* Memory budget callout strip */}
        <g>
          <rect x={40} y={368} width={1680} height={38} rx={4} fill="#ffffff" stroke="#d0d0c8" strokeWidth={1} />
          <text x={56} y={392} style={{ font: '600 13px var(--mono)', fill: 'var(--ink)' }}>
            Total Accelerator BRAMs: 24 (Hash) + 15 (Slots) + 64 (Price RAM) + 2 (Occupancy) + 2 (CDC FIFO) = 107 RAMB36E1 Primitives
          </text>
          <text x={1080} y={392} style={{ font: '700 13px var(--mono)', fill: 'var(--navy)' }}>
            Artix-7 XC7A100T Utilization: 107 / 135 BRAMs (79.3%)
          </text>
          <text x={1520} y={392} style={{ font: '700 13px var(--mono)', fill: 'var(--ok)' }}>
            ✓ Zero Timing Conflicts
          </text>
        </g>

        {/* ════════════════════════════════════════════════════════════════════
            BOTTOM: EXACT 10-CYCLE ADD SCHEDULE & FAIL-STOP INVARIANTS
           ════════════════════════════════════════════════════════════════════ */}
        <SubsystemGroup
          x={20}
          y={430}
          w={1130}
          h={290}
          label="3. Deterministic Add Order Cycle Schedule (lob_core.sv)"
          sub="10 Consecutive Clock Cycles (100 ns total latency @ 100 MHz)"
          isNew
        />

        {/* Schedule Table Header */}
        <g>
          <rect x={36} y={460} width={1098} height={24} fill="#f5f5f3" rx={2} />
          <text x={50} y={476} style={{ font: '700 12px var(--mono)', fill: 'var(--ink-2)' }}>CYCLE</text>
          <text x={120} y={476} style={{ font: '700 12px var(--mono)', fill: 'var(--ink-2)' }}>OPERATION</text>
          <text x={280} y={476} style={{ font: '700 12px var(--mono)', fill: 'var(--ink-2)' }}>HARDWARE ACTION &amp; MEMORY PIPELINE ACCESS</text>
          <line x1={36} y1={484} x2={1134} y2={484} stroke="#dcdcd8" strokeWidth={1} />
        </g>

        {/* 10 Schedule Rows */}
        {[
          ['C0', 'Free Pop & Hash', 'Pop Slot_ID from Free-List FIFO. Compute CRC32-C(Order_ID) hash index in parallel.'],
          ['C1', 'Hash Addr Setup', 'Free-List pop validated. Address hash table set index at RAMB port A.'],
          ['C2', 'Hash BRAM Read', 'Read 4 associative ways from BRAM + parallel CAM stash lookup (1-cycle read latency).'],
          ['C3', 'Hit / Dup Check', 'Verify Order_ID is not already present. Select empty way (or CAM stash overflow).'],
          ['C4', 'Hash BRAM Write', 'Write {Order_ID, Slot_ID} to selected way. Prepare Slot Table write address.'],
          ['C5', 'Slot RAM Write', 'Write {valid=1, side, ID, price, shares} into Slot RAM. Address Price Level RAM.'],
          ['C6', 'Price RAM Read', 'Read current cumulative quantity at {side, price} via Price RAM Port A.'],
          ['C7', 'Quantity Accum', 'Price_Qty <= Price_Qty + Shares. Setup Port B write address.'],
          ['C8', 'Price RAM Write', 'Write updated quantity via Port B. Set corresponding bit in Occupancy Mask.'],
          ['C9', 'BBO Priority Enc', 'Priority Encoder refreshes Best Bid / Best Ask. Strobe complete. Return to IDLE.'],
        ].map(([cyc, op, act], i) => {
          const rowY = 506 + i * 21
          return (
            <g key={cyc}>
              {i % 2 === 1 && (
                <rect x={36} y={rowY - 14} width={1098} height={19} fill="rgba(255,255,255,0.7)" rx={2} />
              )}
              <text x={50} y={rowY} style={{ font: '700 12px var(--mono)', fill: 'var(--navy)' }}>{cyc}</text>
              <text x={120} y={rowY} style={{ font: '600 12px var(--mono)', fill: 'var(--ink)' }}>{op}</text>
              <text x={280} y={rowY} style={{ font: '400 12px var(--mono)', fill: 'var(--ink-2)' }}>{act}</text>
              <line x1={36} y1={rowY + 6} x2={1134} y2={rowY + 6} stroke="#eaeae6" strokeWidth={0.8} />
            </g>
          )
        })}

        {/* ── Section 4: Invariants & Recovery Box ──────────────────────── */}
        <SubsystemGroup
          x={1170}
          y={430}
          w={570}
          h={290}
          label="4. Fail-Safe Invariants &amp; Recovery"
          sub="BOOK_VALID Flag &amp; GLIMPSE Protocol"
        />

        {/* Invariants Header */}
        <text x={1190} y={466} style={{ font: '700 13px var(--mono)', fill: 'var(--warn)', letterSpacing: '.06em' }}>
          DETERMINISTIC FAIL-STOP TRIGGERS:
        </text>

        {/* Invariant Bullet Points */}
        <g>
          <text x={1190} y={492} style={{ font: '500 13px var(--mono)', fill: 'var(--ink-2)' }}>
            <tspan style={{ fill: 'var(--warn)', fontWeight: 700 }}>• Free-List Underflow: </tspan>
            Capacity of 4,096 active orders exceeded
          </text>
          <text x={1190} y={516} style={{ font: '500 13px var(--mono)', fill: 'var(--ink-2)' }}>
            <tspan style={{ fill: 'var(--warn)', fontWeight: 700 }}>• Hash Table + Stash Full: </tspan>
            4-way set and 16-entry stash all occupied
          </text>
          <text x={1190} y={540} style={{ font: '500 13px var(--mono)', fill: 'var(--ink-2)' }}>
            <tspan style={{ fill: 'var(--warn)', fontWeight: 700 }}>• Missing / Duplicate ID: </tspan>
            Lookup miss on cancel, hit on add
          </text>
          <text x={1190} y={564} style={{ font: '500 13px var(--mono)', fill: 'var(--ink-2)' }}>
            <tspan style={{ fill: 'var(--warn)', fontWeight: 700 }}>• Sequence Gap: </tspan>
            MoldUDP64 seq num &gt; expected seq num
          </text>
        </g>

        {/* Recovery Card */}
        <g>
          <rect x={1190} y={590} width={530} height={115} rx={4} fill="#ffffff" stroke="var(--warn)" strokeWidth={1.5} />
          <text x={1208} y={615} style={{ font: '700 12px var(--mono)', fill: 'var(--warn)', letterSpacing: '.06em' }}>
            RECOVERY PROTOCOL (TCP GLIMPSE):
          </text>
          <text x={1208} y={638} style={{ font: '400 13px var(--font)', fill: 'var(--ink)' }}>
            Hardware transitions to <tspan style={{ fontFamily: 'var(--mono)', fontWeight: 600, fill: 'var(--warn)' }}>INVALID</tspan>, asserts <tspan style={{ fontFamily: 'var(--mono)', fontWeight: 600 }}>BOOK_VALID = 0</tspan>, halts matching.
          </text>
          <text x={1208} y={660} style={{ font: '400 13px var(--font)', fill: 'var(--ink)' }}>
            CPU resets book, downloads TCP GLIMPSE snapshot, injects orders via MMIO,
          </text>
          <text x={1208} y={682} style={{ font: '400 13px var(--font)', fill: 'var(--ink)' }}>
            and restores <tspan style={{ fontFamily: 'var(--mono)', fontWeight: 600, fill: 'var(--ok)' }}>BOOK_VALID = 1</tspan> without rebooting the FPGA.
          </text>
        </g>
      </svg>
    </div>
  )
}
