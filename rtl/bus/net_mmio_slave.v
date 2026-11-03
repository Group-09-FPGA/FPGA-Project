// Network Diagnostics MMIO Slave (CPU bus address 0x5000_0000)
//
// Presents the 352-bit net_diag_snapshot (already clock-domain-crossed from
// clk_eth to clk_core via config_cdc) as an 11-register read-only window to
// the CPU bus.
//
// Timing architecture:
//   The snapshot arrives already registered by config_cdc.  To keep it fully
//   isolated from the CPU pipeline's combinational timing arc we pre-register
//   all 11 snapshot words into local regs on every cycle (latching stage), and
//   then mux from those regs into rdata (mux stage).  This gives Vivado two
//   clean register-to-register hops:
//
//   [config_cdc dst_data_reg] → [snap_reg[N]] → [rdata_reg]
//
//   Neither hop crosses the CPU clock domain boundary, and neither depends on
//   any CPU pipeline signal, so the worst path cannot start inside u_cpu.
//
// Read latency: 2 cycles (addr sampled → rsp_valid asserted with rdata).
// Write operations are silently ignored (read-only slave).
//
// Register map (byte-addressed offsets from 0x5000_0000):
//   0x00  cnt_rx_frames   [351:320]
//   0x04  cnt_crc_err     [319:288]
//   0x08  cnt_mold_msgs   [287:256]
//   0x0C  cnt_seq_gaps    [255:224]
//   0x10  cnt_len_err     [223:192]
//   0x14  cnt_phy_err     [191:160]
//   0x18  cnt_overflow_err[159:128]
//   0x1C  cnt_mold_trunc  [127: 96]
//   0x20  status_flags    [ 31:  0]  {29'd0, itch_err, seq_gap, feed_loss}
//   0x24  cnt_udp_len_err [ 95: 64]
//   0x28  cnt_udp_csum_err[ 63: 32]

`timescale 1ns/1ps

module net_mmio_slave (
    input  wire         clk,
    input  wire         reset,          // active-low synchronous reset

    // CPU bus interface (read-only slave)
    input  wire         bus_req_valid,
    input  wire [ 7:0]  bus_req_addr,   // offset within 0x5000_0000 window
    output reg          bus_rsp_valid,
    output reg  [31:0]  bus_rsp_rdata,

    // Network diagnostic snapshot (352-bit, already in clk_core domain)
    input  wire [351:0] net_diag_snapshot
);

    // Stage 0: Latching stage — register every snapshot slice every cycle.
    // This is a pure register stage with no address dependency.  Vivado will
    // place these FFs close to the config_cdc dst_data_reg cells, keeping the
    // fan-in of the mux entirely within the local net MMIO region.
    reg [31:0] snap_cnt_rx_frames;
    reg [31:0] snap_cnt_crc_err;
    reg [31:0] snap_cnt_mold_msgs;
    reg [31:0] snap_cnt_seq_gaps;
    reg [31:0] snap_cnt_len_err;
    reg [31:0] snap_cnt_phy_err;
    reg [31:0] snap_cnt_overflow_err;
    reg [31:0] snap_cnt_mold_trunc;
    reg [31:0] snap_cnt_udp_len_err;
    reg [31:0] snap_cnt_udp_csum_err;
    reg [31:0] snap_status_flags;

    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            snap_cnt_rx_frames    <= 32'd0;
            snap_cnt_crc_err      <= 32'd0;
            snap_cnt_mold_msgs    <= 32'd0;
            snap_cnt_seq_gaps     <= 32'd0;
            snap_cnt_len_err      <= 32'd0;
            snap_cnt_phy_err      <= 32'd0;
            snap_cnt_overflow_err <= 32'd0;
            snap_cnt_mold_trunc   <= 32'd0;
            snap_cnt_udp_len_err  <= 32'd0;
            snap_cnt_udp_csum_err <= 32'd0;
            snap_status_flags     <= 32'd0;
        end else begin
            snap_cnt_rx_frames    <= net_diag_snapshot[351:320];
            snap_cnt_crc_err      <= net_diag_snapshot[319:288];
            snap_cnt_mold_msgs    <= net_diag_snapshot[287:256];
            snap_cnt_seq_gaps     <= net_diag_snapshot[255:224];
            snap_cnt_len_err      <= net_diag_snapshot[223:192];
            snap_cnt_phy_err      <= net_diag_snapshot[191:160];
            snap_cnt_overflow_err <= net_diag_snapshot[159:128];
            snap_cnt_mold_trunc   <= net_diag_snapshot[127: 96];
            snap_cnt_udp_len_err  <= net_diag_snapshot[ 95: 64];
            snap_cnt_udp_csum_err <= net_diag_snapshot[ 63: 32];
            snap_status_flags     <= net_diag_snapshot[ 31:  0];
        end
    end

    // Stage 1: Address pipeline — sample the request address one cycle early.
    reg         req_pending;
    reg  [7:0]  req_addr_d;

    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            req_pending <= 1'b0;
            req_addr_d  <= 8'd0;
        end else begin
            req_pending <= bus_req_valid;
            if (bus_req_valid)
                req_addr_d <= bus_req_addr;
        end
    end

    // Stage 2: Mux + output register — reads only from snap_* FFs (Stage 0).
    // No combinational path from any CPU signal reaches this mux.
    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            bus_rsp_valid <= 1'b0;
            bus_rsp_rdata <= 32'd0;
        end else begin
            bus_rsp_valid <= req_pending;
            if (req_pending) begin
                case (req_addr_d)
                    8'h00:   bus_rsp_rdata <= snap_cnt_rx_frames;
                    8'h04:   bus_rsp_rdata <= snap_cnt_crc_err;
                    8'h08:   bus_rsp_rdata <= snap_cnt_mold_msgs;
                    8'h0C:   bus_rsp_rdata <= snap_cnt_seq_gaps;
                    8'h10:   bus_rsp_rdata <= snap_cnt_len_err;
                    8'h14:   bus_rsp_rdata <= snap_cnt_phy_err;
                    8'h18:   bus_rsp_rdata <= snap_cnt_overflow_err;
                    8'h1C:   bus_rsp_rdata <= snap_cnt_mold_trunc;
                    8'h20:   bus_rsp_rdata <= snap_status_flags;
                    8'h24:   bus_rsp_rdata <= snap_cnt_udp_len_err;
                    8'h28:   bus_rsp_rdata <= snap_cnt_udp_csum_err;
                    default: bus_rsp_rdata <= 32'd0;
                endcase
            end
        end
    end

endmodule
