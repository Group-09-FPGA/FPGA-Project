// ─── Packet Journey scene data ────────────────────────────────────────────────
//
// Camera positions are in Three.js world space after the model is auto-centred
// and scaled so its longest dimension = 8 units.  Board lies roughly flat in
// the XZ plane, Y = up.  Approximate layout:
//
//   Ethernet jack → (+X, −Z) corner
//   FPGA chip      → (0,   0) centre
//   7-seg/buttons  → (+Z)  front edge
//   USB / UART     → (−X, −Z) corner
//
// Tune camPos / camLook once you see the model in the browser.

export interface Signal { name: string; value: string }

export interface Scene {
  id: string
  sceneNum: string
  label: string
  title: string
  body: string
  signals: Signal[]
  accent: 'green' | 'navy' | 'amber' | 'cyan'
  /** Camera world position [x, y, z] */
  camPos: [number, number, number]
  /** Camera look-at target [x, y, z] */
  camLook: [number, number, number]
}

export const SCENES: Scene[] = [
  {
    id: 'cold-open',
    sceneNum: '00',
    label: 'MARKET FEED',
    title: 'A market order enters the network',
    body:
      'NSE broadcasts a MoldUDP64 datagram. 10:31:22.000003 UTC+5:30. Encoded inside: BUY 300 shares of RELIANCE @ 2457.50.',
    signals: [
      { name: 'raw bytes', value: '45 00 00 3c a3 d2 40 00 40 11 …' },
      { name: 'timestamp', value: '10:31:22.000003' },
    ],
    accent: 'amber',
    camPos: [0, 11, 10],
    camLook: [0, 0, 0],
  },
  {
    id: 'rmii',
    sceneNum: '01',
    label: 'ETHERNET · RMII RX',
    title: 'Physical layer: 2-bit dibits at 50 MHz',
    body:
      'The RMII interface receives 2 bits per clock. The PHY runs at 50 MHz — 100 Mbit/s throughput. Preamble and SFD are stripped, then the payload bytes stream into the FPGA.',
    signals: [
      { name: 'rmii_rxd[1:0]', value: "2'b10" },
      { name: 'rmii_crs_dv',   value: "1'b1" },
      { name: 'clk_eth',       value: '50 MHz' },
    ],
    accent: 'green',
    camPos: [5, 5, -6],
    camLook: [3, 0, -3],
  },
  {
    id: 'fcs',
    sceneNum: '02',
    label: 'FCS · NET PARSER',
    title: 'CRC-32 verified. IPv4 + UDP headers stripped.',
    body:
      'net_parser validates the 32-bit frame checksum, then extracts IPv4 and UDP headers. Destination port 10443 identifies the MoldUDP64 payload boundary.',
    signals: [
      { name: 'eth_fcs_ok',    value: "1'b1" },
      { name: 'udp_dst_port',  value: "16'd10443" },
      { name: 'pkt_valid',     value: "1'b1" },
      { name: 'crc_err',       value: "1'b0" },
    ],
    accent: 'green',
    camPos: [4, 4, -4],
    camLook: [2, 0, -2],
  },
  {
    id: 'moldudp64',
    sceneNum: '03',
    label: 'MOLDUDP64',
    title: 'Sequence number verified. No gap detected.',
    body:
      'MoldUDP64 wraps ITCH messages with a session ID and a monotonic 64-bit sequence number. Seq #18,342. No gap — the book stays valid and the pipeline continues.',
    signals: [
      { name: 'session_id',  value: '"A         "' },
      { name: 'seq_num',     value: "64'd18342" },
      { name: 'msg_count',   value: "16'd1" },
      { name: 'gap_detected', value: "1'b0" },
    ],
    accent: 'navy',
    camPos: [2, 5, -2],
    camLook: [0, 0, -1],
  },
  {
    id: 'itch',
    sceneNum: '04',
    label: 'ITCH 5.0 DECODER',
    title: "Type 'A' Add Order — 28 bytes decoded",
    body:
      "itch_decoder identifies message type 0x41 ('A') and extracts every field in one clock cycle at 50 MHz: order ID, side, shares, and raw price.",
    signals: [
      { name: 'msg_type',  value: "8'h41  // 'A'" },
      { name: 'order_id',  value: "64'hDEADBEEF01234567" },
      { name: 'side',      value: "8'h42  // 'B' = Buy" },
      { name: 'qty',       value: "32'd300" },
      { name: 'price',     value: "32'd245750000  // × 10⁻⁴" },
    ],
    accent: 'navy',
    camPos: [1, 4, 1],
    camLook: [0, 0, 0],
  },
  {
    id: 'event',
    sceneNum: '05',
    label: '256-BIT CANONICAL EVENT',
    title: 'One wide word encodes the full order',
    body:
      'itch_decoder emits a single 256-bit event: OP code, order ID, quantity, price index (PIDX), and timestamp. One word, one cycle — the LOB core never needs to re-parse.',
    signals: [
      { name: 'evt[255:248]', value: "8'h11  // VER=1, OP=ADD" },
      { name: 'evt[247]',     value: "1'b1   // SIDE=BUY" },
      { name: 'evt[239:176]', value: "64'hDEADBEEF01234567  // OID" },
      { name: 'evt[95:64]',   value: "32'd300  // QTY" },
      { name: 'evt[44:32]',   value: "13'd491  // PIDX" },
    ],
    accent: 'navy',
    camPos: [0, 3, 0],
    camLook: [0, 0, 0],
  },
  {
    id: 'fifo',
    sceneNum: '06',
    label: 'ASYNC FIFO · CLOCK CROSSING',
    title: '50 MHz → 100 MHz. No data lost.',
    body:
      'An asynchronous FIFO with Gray-coded read/write pointers safely bridges two independent clock domains. The LOB core runs at 100 MHz — double the Ethernet clock — for lower per-event latency.',
    signals: [
      { name: 'wr_clk',     value: '50 MHz' },
      { name: 'rd_clk',     value: '100 MHz' },
      { name: 'fifo_full',  value: "1'b0" },
      { name: 'fifo_empty', value: "1'b0" },
    ],
    accent: 'amber',
    camPos: [-2, 7, 3],
    camLook: [0, 0, 0],
  },
  {
    id: 'hash',
    sceneNum: '07',
    label: 'HASH TABLE · SLOT ALLOCATION',
    title: '1024-bucket 8-way CAM. Slot found.',
    body:
      'The 64-bit order ID is hashed to a 10-bit bucket index. An 8-way set-associative CAM lookup either finds the existing slot (cancel/replace) or allocates a new one from the free-list LIFO stack.',
    signals: [
      { name: 'hash_idx',    value: "10'd731" },
      { name: 'cam_hit',     value: "1'b0  // new order" },
      { name: 'slot_num',    value: "11'd1847" },
      { name: 'freelist_ptr', value: "11'd2046" },
    ],
    accent: 'navy',
    camPos: [1, 3, 1],
    camLook: [0, 0, 0],
  },
  {
    id: 'priceram',
    sceneNum: '08',
    label: 'PRICE RAM · BOOK UPDATE',
    title: 'Bid qty at price index 491: 0 → 300',
    body:
      'The slot table records {side=BUY, pidx=491, qty=300}. The Price RAM — split into bid and ask banks — updates the aggregate quantity at that price level in 6 cycles.',
    signals: [
      { name: 'pidx',          value: "13'd491" },
      { name: 'price_ram_rd',  value: "32'd0" },
      { name: 'price_ram_wr',  value: "32'd300" },
      { name: 'bank',          value: 'BID' },
    ],
    accent: 'green',
    camPos: [-1, 3, 2],
    camLook: [0, 0, 1],
  },
  {
    id: 'bbo',
    sceneNum: '09',
    label: 'OCCUPANCY BITMAP · BBO ENGINE',
    title: 'Best bid found in 6 cycles = 60 ns',
    body:
      'The 3-level occupancy bitmap (L0/L1/L2) marks PIDX 491 occupied and triggers a BBO search. A DSP48E1 computes: best_bid = base_price + pidx × tick_size = 2457.50.',
    signals: [
      { name: 'occ_bit[491]',   value: "1'b1 (set)" },
      { name: 'bbo_latency',    value: '6 cycles @ 100 MHz' },
      { name: 'best_bid',       value: "32'd245750000" },
      { name: 'best_bid_valid', value: "1'b1" },
    ],
    accent: 'green',
    camPos: [0, 3, 2],
    camLook: [0, 0, 0],
  },
  {
    id: 'mmio',
    sceneNum: '10',
    label: 'MMIO · RV32IM CPU',
    title: 'Firmware reads BBO via MMIO',
    body:
      'The RV32IM softcore runs a firmware polling loop: lw a0, 0(gp) reads the best-bid snapshot register at 0x4000_0000. The CPU never touches the per-event path — it only observes the result.',
    signals: [
      { name: 'mmio_addr',  value: "32'h4000_0000" },
      { name: 'mmio_rdata', value: "32'h0EB4_EF40" },
      { name: 'cpu_instr',  value: 'lw a0, 0(gp)' },
      { name: 'pc',         value: "32'h0000_00A4" },
    ],
    accent: 'cyan',
    camPos: [-4, 4, -1],
    camLook: [-2, 0, 0],
  },
  {
    id: 'outputs',
    sceneNum: '11',
    label: 'OUTPUTS · BOARD',
    title: 'Best bid/ask live on the board',
    body:
      'UART transmits the BBO snapshot at 115200 baud. The 7-segment display shows the price. LEDs confirm pipeline health. One market order — through 11 RTL stages — in 60 ns.',
    signals: [
      { name: 'uart_tx',  value: '0xEB 0x4E 0xF4 0x00 …' },
      { name: '7seg',     value: '2457.50' },
      { name: 'led[0]',   value: "1'b1  // pkt_ok" },
      { name: 'led[1]',   value: "1'b1  // bbo_valid" },
    ],
    accent: 'green',
    camPos: [0, 10, 9],
    camLook: [0, 0, 1],
  },
]
