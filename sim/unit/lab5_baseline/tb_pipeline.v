`timescale 1ns / 1ps

module tb_pipeline;

////////////////////////////////////////////////////////////
// CLOCK & RESET
////////////////////////////////////////////////////////////
reg clk;
reg reset;

// 100 MHz clock
initial begin
	clk = 0;
	forever #5 clk = ~clk;
end

// reset (active low in our CPU)
initial begin
	reset = 0;
	#100;
	reset = 1;
end


////////////////////////////////////////////////////////////
// PIPE ↔ MEMORY SIGNALS
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

wire exception;
wire [31:0] pc_out;


////////////////////////////////////////////////////////////
// DUT : PIPELINE CPU
////////////////////////////////////////////////////////////
// TODO completed, description: Connected all port signals including memory interface and pc_out to DUT pipe
pipe DUT (
	.clk(clk),
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
// TODO completed, description: Connected inst_mem_address as a port signal from the pipe
instr_mem IMEM (
	.clk(clk),
	.pc(inst_mem_address),
	.instr(inst_mem_read_data)
);


////////////////////////////////////////////////////////////
// DATA MEMORY  (matches data_mem.v)
////////////////////////////////////////////////////////////
// TODO completed, description: Connected all read and write signals from the pipe to DMEM
data_mem DMEM (
	.clk(clk),

	.re(dmem_read_ready),
	.raddr(dmem_read_address),
	.rdata(dmem_read_data),

	.we(dmem_write_ready),
	.waddr(dmem_write_address),
	.wdata(dmem_write_data),
	.wstrb(dmem_write_byte)
);


////////////////////////////////////////////////////////////
// SIMULATION TIME & LOGGING
////////////////////////////////////////////////////////////
initial begin
	$dumpfile("pipeline.vcd");
	$dumpvars(0, tb_pipeline);
	#20000;   // run long enough to see program execute
	$finish;
end










always @(posedge clk) begin
    if (reset) begin
        $display("next_pc = %08x", DUT.fetch_pc);
        
        // Print the ALU writes to track results
        if (DUT.wb_reg_write_en && DUT.wb_dest_reg_sel == 15 && !DUT.wb_stall && !DUT.wb_mem_to_reg) begin
            $display("time:\t%10t ,result =\t%10d", $time, $signed(DUT.wb_result));
        end
        
        // Dynamic stop condition for ALL workloads
        if (DUT.inst_mem_read_data == 32'h00008067) begin
            $display("All instructions are Fetched");
            $display("next_pc = 00000000");
            #10 $finish;
        end
    end
end

endmodule
