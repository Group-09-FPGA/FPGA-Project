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
        <div style={{ position: 'absolute', left: 40, top: 370, width: 1680 }}>
          <div style={{ background: '#ffffff', border: '1px solid #d0d0c8', padding: '10px 16px', borderRadius: 4, display: 'flex', justifyContent: 'space-between', alignItems: 'center', font: '13px var(--mono)' }}>
            <div><b>Total Accelerator BRAMs:</b> 24 (Hash) + 15 (Slots) + 64 (Price RAM) + 2 (Occupancy) + 2 (CDC FIFO) = <b>107 RAMB36E1 Primitives</b></div>
            <div style={{ color: 'var(--navy)', fontWeight: 600 }}>Artix-7 XC7A100T Utilization: 107 / 135 BRAMs (79.3%)</div>
            <div style={{ color: 'var(--ok)', fontWeight: 600 }}>Zero Timing Conflicts (Dual-Port Port Sched)</div>
          </div>
        </div>

        {/* ════════════════════════════════════════════════════════════════════
            BOTTOM: EXACT 10-CYCLE ADD SCHEDULE & FAIL-STOP INVARIANTS
           ════════════════════════════════════════════════════════════════════ */}
        <SubsystemGroup
          x={20}
          y={460}
          w={1130}
          h={260}
          label="3. Deterministic Add Order Cycle Schedule (lob_core.sv)"
          sub="10 Consecutive Clock Cycles (100 ns total latency @ 100 MHz)"
          isNew
        />

        <div style={{ position: 'absolute', left: 40, top: 495, width: 1090 }}>
          <table style={{ width: '100%', borderCollapse: 'collapse', font: '12px var(--mono)' }}>
            <thead>
              <tr style={{ borderBottom: '1.5px solid var(--line)', textAlign: 'left', color: 'var(--ink-3)' }}>
                <th style={{ width: 60, padding: '4px' }}>Cycle</th>
                <th style={{ width: 180, padding: '4px' }}>Operation</th>
                <th style={{ padding: '4px' }}>Hardware Action &amp; Memory Access</th>
              </tr>
            </thead>
            <tbody>
              {[
                ['C0', 'Free Pop & Hash', 'Pop Slot_ID from Free-List FIFO. Simultaneously calculate CRC32-C(Order_ID).'],
                ['C1', 'Hash Addr Setup', 'Free-List pop validated. Address hash table set index at RAMB port A.'],
                ['C2', 'Hash BRAM Read', 'Read 4 associative ways from BRAM + parallel CAM stash lookup.'],
                ['C3', 'Hit / Dup Check', 'Verify Order_ID is not already present. Select empty way (or stash overflow).'],
                ['C4', 'Hash BRAM Write', 'Write {Order_ID, Slot_ID} to selected way. Prepare Slot Table write address.'],
                ['C5', 'Slot RAM Write', 'Write {valid=1, side, ID, price, shares} into Slot RAM. Address Price Level RAM.'],
                ['C6', 'Price RAM Read', 'Read current cumulative quantity at {side, price} via Price RAM Port A.'],
                ['C7', 'Quantity Accum', 'Price_Qty <= Price_Qty + Shares. Setup Port B write address.'],
                ['C8', 'Price RAM Write', 'Write updated quantity via Port B. Set corresponding bit in Occupancy Mask.'],
                ['C9', 'BBO Priority Enc', 'Priority Encoder refreshes Best Bid / Best Ask. Strobe complete. Return to IDLE.'],
              ].map(([cyc, op, act]) => (
                <tr key={cyc} style={{ borderBottom: '1px solid #e8e8e4' }}>
                  <td style={{ padding: '3px 4px', fontWeight: 700, color: 'var(--navy)' }}>{cyc}</td>
                  <td style={{ padding: '3px 4px', fontWeight: 600, color: 'var(--ink)' }}>{op}</td>
                  <td style={{ padding: '3px 4px', color: 'var(--ink-2)' }}>{act}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        {/* ── Invariants & Fail-Stop Box ─────────────────────────────────── */}
        <SubsystemGroup
          x={1170}
          y={460}
          w={570}
          h={260}
          label="4. Fail-Safe Invariants &amp; Recovery"
          sub="BOOK_VALID Flag &amp; GLIMPSE Protocol"
        />

        <div style={{ position: 'absolute', left: 1190, top: 495, width: 530, font: '13px/1.45 var(--font)', color: 'var(--ink-2)' }}>
          <div style={{ font: '600 13px var(--mono)', color: 'var(--warn)', letterSpacing: '.06em', textTransform: 'uppercase' }}>
            Deterministic Fail-Stop Triggers:
          </div>
          <ul style={{ margin: '6px 0 0 18px', display: 'grid', gap: 4 }}>
            <li><b>Free-List Underflow:</b> Book capacity of 4,096 active orders exceeded.</li>
            <li><b>Hash Table + Stash Full:</b> 4-way set and 16-entry stash all occupied.</li>
            <li><b>Missing / Duplicate Order ID:</b> Lookup miss on cancel, hit on add.</li>
            <li><b>Sequence Gap:</b> MoldUDP64 seq num &gt; expected seq num.</li>
          </ul>

          <div style={{ marginTop: 12, padding: '10px 14px', background: '#ffffff', border: '1.5px solid var(--warn)', borderRadius: 4 }}>
            <div style={{ font: '700 12px var(--mono)', color: 'var(--warn)' }}>RECOVERY PROTOCOL:</div>
            <div style={{ fontSize: 13, marginTop: 2 }}>
              Hardware transitions to <code>INVALID</code>, asserts <code>BOOK_VALID = 0</code>, halts matching. CPU resets book, downloads TCP GLIMPSE snapshot, injects orders via MMIO, and restores <code>VALID</code>.
            </div>
          </div>
        </div>
      </svg>
    </div>
  )
}
