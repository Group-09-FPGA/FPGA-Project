`timescale 1ns / 1ps

module top_fpga #(
	parameter IMEMSIZE = 4096,
	parameter DMEMSIZE = 4096
)(
	input  wire clk,   // fast board clock (100 MHz)
	input  wire reset, // active-low reset

	output [15:0] led, // shows dmem_write_data[15:0]: verifies STORE results

	// 7-segment display: shows fetch_pc as 8 hex digits
	output [7:0]  an,  // anode select, active-low
	output [6:0]  seg, // segment select, active-low {CG..CA}
	output        dp   // decimal point (always off)
);

wire exception;
wire [31:0] pc_out;

// Changed from pc_out to dmem_write_data: directly verifies STORE instructions executed by the CPU
// Moved below wire declaration

	////////////////////////////////////////////////////////////
	// Slow clock generator (clock divider)
	////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////
// 100 MHz → 1 Hz clock divider (Nexys A7)
////////////////////////////////////////////////////////////
reg [25:0] clk_cnt;   	// enough for 50 million
reg    	slow_clk;

always @(posedge clk or negedge reset) begin
	if (!reset) begin
    	clk_cnt  <= 26'd0;
    	slow_clk <= 1'b0;
	end else begin
    	if (clk_cnt == 26'd49_999_999) begin
        	clk_cnt  <= 26'd0;
        	slow_clk <= ~slow_clk;   // toggle every 0.5 sec
    	end else begin
        	clk_cnt <= clk_cnt + 1'b1;
    	end
	end
end


	////////////////////////////////////////////////////////////
	// PIPE ↔ BUS WIRES
	////////////////////////////////////////////////////////////
    wire        bus_req_valid;
    wire        bus_req_write;
    wire [31:0] bus_req_addr;
    wire [31:0] bus_req_wdata;
    wire [ 3:0] bus_req_wstrb;
    wire        bus_rsp_valid;
    wire [31:0] bus_rsp_rdata;
    wire        bus_rsp_error;
    
    // Slaves
    wire        imem_req_valid;
    wire        imem_req_write;
    wire [31:0] imem_req_addr;
    wire [31:0] imem_req_wdata;
    wire [ 3:0] imem_req_wstrb;
    wire        imem_rsp_valid;
    wire [31:0] imem_rsp_rdata;

    wire        dmem_req_valid;
    wire        dmem_req_write;
    wire [31:0] dmem_req_addr;
    wire [31:0] dmem_req_wdata;
    wire [ 3:0] dmem_req_wstrb;
    wire        dmem_rsp_valid;
    wire [31:0] dmem_rsp_rdata;

    // Optional delay for DMEM (can be changed to test delayed slave)
    parameter DMEM_DELAY_CYCLES = 0;
	
	assign led = bus_req_wdata[15:0]; // Shows the write data currently on the bus

////////////////////////////////////////////////////////////
// PIPELINE CPU
////////////////////////////////////////////////////////////
// BUG fixed: Switched .clk to slow_clk so that CPU execution is visible on LEDs on FPGA hardware
// TODO completed, description: Connected all memory interface ports to cpu_core instance
cpu_core pipe_u (
	.clk(slow_clk),
	.reset(reset),
	.stall(1'b0),
	.exception(exception),
	.pc_out(pc_out),

    .bus_req_valid(bus_req_valid),
    .bus_req_write(bus_req_write),
    .bus_req_addr(bus_req_addr),
    .bus_req_wdata(bus_req_wdata),
    .bus_req_wstrb(bus_req_wstrb),
    .bus_rsp_valid(bus_rsp_valid),
    .bus_rsp_rdata(bus_rsp_rdata),
    .bus_rsp_error(bus_rsp_error)
);

sys_bus_interconnect interconnect_u (
    .clk(slow_clk),
    .reset(reset),
    .cpu_req_valid(bus_req_valid),
    .cpu_req_write(bus_req_write),
    .cpu_req_addr(bus_req_addr),
    .cpu_req_wdata(bus_req_wdata),
    .cpu_req_wstrb(bus_req_wstrb),
    .cpu_rsp_valid(bus_rsp_valid),
    .cpu_rsp_rdata(bus_rsp_rdata),
    .cpu_rsp_error(bus_rsp_error),
    
    .imem_req_valid(imem_req_valid),
    .imem_req_write(imem_req_write),
    .imem_req_addr(imem_req_addr),
    .imem_req_wdata(imem_req_wdata),
    .imem_req_wstrb(imem_req_wstrb),
    .imem_rsp_valid(imem_rsp_valid),
    .imem_rsp_rdata(imem_rsp_rdata),
    
    .dmem_req_valid(dmem_req_valid),
    .dmem_req_write(dmem_req_write),
    .dmem_req_addr(dmem_req_addr),
    .dmem_req_wdata(dmem_req_wdata),
    .dmem_req_wstrb(dmem_req_wstrb),
    .dmem_rsp_valid(dmem_rsp_valid),
    .dmem_rsp_rdata(dmem_rsp_rdata)
);


////////////////////////////////////////////////////////////
// INSTRUCTION MEMORY SLAVE
////////////////////////////////////////////////////////////
imem_slave imem_u (
    .clk(slow_clk),
    .reset(reset),
    .req_valid(imem_req_valid),
    .req_write(imem_req_write),
    .req_addr(imem_req_addr),
    .req_wdata(imem_req_wdata),
    .req_wstrb(imem_req_wstrb),
    .rsp_valid(imem_rsp_valid),
    .rsp_rdata(imem_rsp_rdata)
);

////////////////////////////////////////////////////////////
// DATA MEMORY SLAVE
////////////////////////////////////////////////////////////
dmem_slave #(
    .DELAY_CYCLES(DMEM_DELAY_CYCLES)
) dmem_u (
    .clk(slow_clk),
    .reset(reset),
    .req_valid(dmem_req_valid),
    .req_write(dmem_req_write),
    .req_addr(dmem_req_addr),
    .req_wdata(dmem_req_wdata),
    .req_wstrb(dmem_req_wstrb),
    .rsp_valid(dmem_rsp_valid),
    .rsp_rdata(dmem_rsp_rdata)
);

////////////////////////////////////////////////////////////
// 7-SEGMENT DISPLAY DRIVER
// Displays fetch_pc as 8 hex digits (e.g. 00000004 = PC=4)
// Uses fast clk (100 MHz) for proper multiplexed refresh.
// The slow CPU clock is NOT used here - the 7-seg mux must
// run fast enough that all 8 digits appear solid to the eye.
////////////////////////////////////////////////////////////
seven_seg_driver seg_u (
	.clk   (clk),
	.reset (reset),
	.value (pc_out),   // show current fetch PC
	.an    (an),
	.seg   (seg),
	.dp    (dp)
);

endmodule