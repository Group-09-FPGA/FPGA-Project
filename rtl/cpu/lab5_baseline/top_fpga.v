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
	// PIPE ↔ MEMORY WIRES
	////////////////////////////////////////////////////////////
	wire [31:0] inst_mem_read_data;
	wire [31:0] inst_mem_address;
	wire    	inst_mem_is_valid;

	wire [31:0] dmem_read_data;
	wire        dmem_read_ready;
	wire [31:0] dmem_read_address;
	wire        dmem_write_ready;
	wire [31:0] dmem_write_address;
	wire [31:0] dmem_write_data;
	wire [3:0]  dmem_write_byte;
	wire    	dmem_write_valid;
	wire    	dmem_read_valid;

	assign inst_mem_is_valid = 1'b1;
	assign dmem_write_valid  = 1'b1;
	assign dmem_read_valid   = 1'b1;
	
	assign led = dmem_write_data[15:0];

////////////////////////////////////////////////////////////
// PIPELINE CPU
////////////////////////////////////////////////////////////
// BUG fixed: Switched .clk to slow_clk so that CPU execution is visible on LEDs on FPGA hardware
// TODO completed, description: Connected all memory interface ports to pipe instance
pipe pipe_u (
	.clk(slow_clk),
	.reset(reset),
	.stall(1'b0),
	.exception(exception),
	.pc_out(pc_out),

	.inst_mem_is_valid(inst_mem_is_valid),
	.inst_mem_read_data(inst_mem_read_data),
	.inst_mem_address(inst_mem_address),

	.dmem_read_data_temp(dmem_read_data),
	.dmem_write_valid(dmem_write_valid),
	.dmem_read_valid(dmem_read_valid),
	.dmem_read_ready(dmem_read_ready),
	.dmem_read_address(dmem_read_address),
	.dmem_write_ready(dmem_write_ready),
	.dmem_write_address(dmem_write_address),
	.dmem_write_data(dmem_write_data),
	.dmem_write_byte(dmem_write_byte)
);


////////////////////////////////////////////////////////////
// INSTRUCTION MEMORY  (matches instr_mem.v)
////////////////////////////////////////////////////////////
// TODO completed, description: Connected inst_mem_address as port signal from pipe to IMEM
instr_mem IMEM (
	.clk(slow_clk),
	.pc(inst_mem_address),
	.instr(inst_mem_read_data)
);


////////////////////////////////////////////////////////////
// DATA MEMORY  (matches data_mem.v)
////////////////////////////////////////////////////////////
// TODO completed, description: Connected dmem read/write signals from pipe to DMEM
data_mem DMEM (
	.clk(slow_clk),

	.re(dmem_read_ready),
	.raddr(dmem_read_address),

	.we(dmem_write_ready),
	.waddr(dmem_write_address),
	.wdata(dmem_write_data),
	.wstrb(dmem_write_byte),
	//output
	.rdata(dmem_read_data)
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