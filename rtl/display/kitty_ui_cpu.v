`timescale 1ns/1ps
// A second instance of the project's RV32IM core runs presentation firmware.
// It has no path to inject book orders: only read-only book RAM queries and
// writes to private video buffers. The existing supervisor/LOB remain intact.
module kitty_ui_cpu #(
    parameter FIRMWARE_FILE="kitty_ui.hex"
)(
    input wire clk,reset_n,
    input wire [2047:0] registers,
    output reg ram_request,
    output reg [3:0] ram_kind,
    output reg [13:0] ram_address,
    input wire ram_grant,
    input wire [607:0] ram_data,
    output reg cell_we,
    output reg [13:0] cell_addr,
    output reg [15:0] cell_data,
    output reg plot_we,
    output reg [11:0] plot_addr,
    output reg [31:0] plot_data,
    output reg requested_bank,requested_market,
    input wire front_bank,
    output reg [31:0] completed_frames,
    output wire exception,
    output wire [31:0] pc
);
    wire request,write;
    wire [31:0] address,wdata;
    wire [3:0] lanes;
    reg response;
    reg [31:0] rdata;
    (* ram_style="block" *) reg [31:0] memory[0:16383];
    reg [607:0] result;
    reg [2:0] ram_wait;
    integer b;
    initial $readmemh(FIRMWARE_FILE,memory);
    cpu_core cpu(.clk(clk),.reset(reset_n),.stall(1'b0),.exception(exception),.pc_out(pc),
        .bus_req_valid(request),.bus_req_write(write),.bus_req_addr(address),
        .bus_req_wdata(wdata),.bus_req_wstrb(lanes),
        .bus_rsp_valid(response),.bus_rsp_rdata(rdata),.bus_rsp_error(1'b0));
    // Separate synchronous BRAM port inference from the MMIO response mux.
    reg [31:0] memory_q;
    wire memory_request=request && address[31:16]==0;
    always @(posedge clk) begin
        if(memory_request) begin
            memory_q<=memory[address[15:2]];
            if(write) for(b=0;b<4;b=b+1)
                if(lanes[b]) memory[address[15:2]][b*8+:8]<=wdata[b*8+:8];
        end
    end
    reg memory_response;
    reg mmio_response;
    reg [31:0] mmio_data;
    always @* begin
        response=memory_response || mmio_response;
        rdata=memory_response ? memory_q : mmio_data;
    end
    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            memory_response<=0;mmio_response<=0;mmio_data<=0;
            ram_request<=0;ram_kind<=0;ram_address<=0;ram_wait<=0;result<=0;
            cell_we<=0;cell_addr<=0;cell_data<=0;plot_we<=0;plot_addr<=0;plot_data<=0;
            requested_bank<=0;requested_market<=0;completed_frames<=0;
        end else begin
            memory_response<=memory_request;
            mmio_response<=0;cell_we<=0;plot_we<=0;
            if(ram_request) begin
                if(!ram_grant) ram_wait<=0;
                else if(ram_wait==3) begin
                    result<=ram_data;ram_request<=0;mmio_response<=1;mmio_data<=0;
                end else ram_wait<=ram_wait+1'b1;
            end else if(request && !memory_request) begin
                if(address==32'h10000100 && write) begin
                    ram_request<=1;ram_kind<=wdata[19:16];ram_address<=wdata[13:0];ram_wait<=0;
                end else begin
                    mmio_response<=1;mmio_data<=0;
                    if(address[31:16]==16'h1000) begin
                        if(address[15:8]==0) mmio_data<=registers[address[7:2]*32+:32];
                        else if(address==32'h10000104) mmio_data<={31'd0,front_bank};
                        else if(address==32'h10000108 && write) begin
                            requested_bank<=wdata[0];requested_market<=wdata[1];
                            completed_frames<=completed_frames+1'b1;
                        end else if(address==32'h1000010c) mmio_data<=completed_frames;
                        else if(address>=32'h10000200 && address<32'h1000024c)
                            mmio_data<=result[((address-32'h10000200)>>2)*32+:32];
                    end else if(address[31:16]==16'h3000 && write) begin
                        cell_we<=1;cell_addr<=address[15:2];cell_data<=wdata[15:0];
                    end else if(address[31:16]==16'h4000 && write) begin
                        plot_we<=1;plot_addr<=address[13:2];plot_data<=wdata;
                    end
                end
            end
        end
    end
endmodule
