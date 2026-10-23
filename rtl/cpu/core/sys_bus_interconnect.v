`timescale 1ns/1ps

module sys_bus_interconnect (
    input clk,
    input reset,

    // Master (CPU) Interface
    input         cpu_req_valid,
    input         cpu_req_write,
    input  [31:0] cpu_req_addr,
    input  [31:0] cpu_req_wdata,
    input  [ 3:0] cpu_req_wstrb,
    
    output        cpu_rsp_valid,
    output [31:0] cpu_rsp_rdata,
    output        cpu_rsp_error,

    // Slave 0: IMEM (0x00000000 - 0x00003FFF)
    output        imem_req_valid,
    output        imem_req_write,
    output [31:0] imem_req_addr,
    output [31:0] imem_req_wdata,
    output [ 3:0] imem_req_wstrb,
    input         imem_rsp_valid,
    input  [31:0] imem_rsp_rdata,

    // Slave 1: DMEM (0x20000000 - 0x20003FFF, 0xFFFF0000 - 0xFFFFFFFF)
    output        dmem_req_valid,
    output        dmem_req_write,
    output [31:0] dmem_req_addr,
    output [31:0] dmem_req_wdata,
    output [ 3:0] dmem_req_wstrb,
    input         dmem_rsp_valid,
    input  [31:0] dmem_rsp_rdata,

    // Slave 2: LOB MMIO (0x40000000 - 0x4FFFFFFF)
    output        lob_req_valid,
    output        lob_req_write,
    output [31:0] lob_req_addr,
    output [31:0] lob_req_wdata,
    output [ 3:0] lob_req_wstrb,
    input         lob_rsp_valid,
    input  [31:0] lob_rsp_rdata,

    // Slave 3: NET MMIO (0x50000000 - 0x5FFFFFFF)
    output        net_req_valid,
    output        net_req_write,
    output [31:0] net_req_addr,
    output [31:0] net_req_wdata,
    output [ 3:0] net_req_wstrb,
    input         net_rsp_valid,
    input  [31:0] net_rsp_rdata,

    // Slave 4: UART MMIO (0x60000000 - 0x6FFFFFFF)
    output        uart_req_valid,
    output        uart_req_write,
    output [31:0] uart_req_addr,
    output [31:0] uart_req_wdata,
    output [ 3:0] uart_req_wstrb,
    input         uart_rsp_valid,
    input  [31:0] uart_rsp_rdata,

    // Slave 5: SYS / Board MMIO (0x70000000 - 0x7FFFFFFF)
    output        sys_req_valid,
    output        sys_req_write,
    output [31:0] sys_req_addr,
    output [31:0] sys_req_wdata,
    output [ 3:0] sys_req_wstrb,
    input         sys_rsp_valid,
    input  [31:0] sys_rsp_rdata
);

    // Address Decoding
    // Memories contain 1024 words each. Decode their actual 4-KiB ranges
    // instead of silently aliasing every address in a 256-MiB region.
    wire sel_imem = (cpu_req_addr[31:12] == 20'h00000);
    wire sel_dmem = (cpu_req_addr[31:12] == 20'h20000);
    wire sel_lob  = (cpu_req_addr[31:8] == 24'h400000);
    wire sel_net  = (cpu_req_addr[31:8] == 24'h500000);
    wire sel_uart = (cpu_req_addr[31:8] == 24'h600000);
    wire sel_sys  = (cpu_req_addr[31:8] == 24'h700000);
    
    // We only have one outstanding transaction, so we track which slave was selected
    reg [2:0] slave_sel;
    localparam SEL_NONE = 3'd0;
    localparam SEL_IMEM = 3'd1;
    localparam SEL_DMEM = 3'd2;
    localparam SEL_LOB  = 3'd3;
    localparam SEL_NET  = 3'd4;
    localparam SEL_UART = 3'd5;
    localparam SEL_SYS  = 3'd6;
    localparam SEL_ERR  = 3'd7;
    
    wire active_transaction = (slave_sel != SEL_NONE);
    wire req_en = cpu_req_valid && (!active_transaction || cpu_rsp_valid);
    
    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            slave_sel <= SEL_NONE;
        end else begin
            if (req_en) begin
                if (sel_imem)      slave_sel <= SEL_IMEM;
                else if (sel_dmem) slave_sel <= SEL_DMEM;
                else if (sel_lob)  slave_sel <= SEL_LOB;
                else if (sel_net)  slave_sel <= SEL_NET;
                else if (sel_uart) slave_sel <= SEL_UART;
                else if (sel_sys)  slave_sel <= SEL_SYS;
                else               slave_sel <= SEL_ERR;
            end else if (cpu_rsp_valid) begin
                // Transaction complete
                slave_sel <= SEL_NONE;
            end
        end
    end

    // Route Request
    assign imem_req_valid = req_en && sel_imem;
    assign imem_req_write = cpu_req_write;
    assign imem_req_addr  = cpu_req_addr;
    assign imem_req_wdata = cpu_req_wdata;
    assign imem_req_wstrb = cpu_req_wstrb;

    assign dmem_req_valid = req_en && sel_dmem;
    assign dmem_req_write = cpu_req_write;
    assign dmem_req_addr  = cpu_req_addr;
    assign dmem_req_wdata = cpu_req_wdata;
    assign dmem_req_wstrb = cpu_req_wstrb;

    assign lob_req_valid  = req_en && sel_lob;
    assign lob_req_write  = cpu_req_write;
    assign lob_req_addr   = cpu_req_addr;
    assign lob_req_wdata  = cpu_req_wdata;
    assign lob_req_wstrb  = cpu_req_wstrb;

    assign net_req_valid  = req_en && sel_net;
    assign net_req_write  = cpu_req_write;
    assign net_req_addr   = cpu_req_addr;
    assign net_req_wdata  = cpu_req_wdata;
    assign net_req_wstrb  = cpu_req_wstrb;

    assign uart_req_valid = req_en && sel_uart;
    assign uart_req_write = cpu_req_write;
    assign uart_req_addr  = cpu_req_addr;
    assign uart_req_wdata = cpu_req_wdata;
    assign uart_req_wstrb = cpu_req_wstrb;

    assign sys_req_valid  = req_en && sel_sys;
    assign sys_req_write  = cpu_req_write;
    assign sys_req_addr   = cpu_req_addr;
    assign sys_req_wdata  = cpu_req_wdata;
    assign sys_req_wstrb  = cpu_req_wstrb;

    // Route Response
    // For unmapped addresses, we generate a 1-cycle error response.
    reg err_rsp_valid;
    always @(posedge clk or negedge reset) begin
        if (!reset) err_rsp_valid <= 1'b0;
        else if (req_en && !sel_imem && !sel_dmem && !sel_lob && !sel_net && !sel_uart && !sel_sys)
            err_rsp_valid <= 1'b1;
        else err_rsp_valid <= 1'b0;
    end

    assign cpu_rsp_valid = (slave_sel == SEL_IMEM) ? imem_rsp_valid :
                           (slave_sel == SEL_DMEM) ? dmem_rsp_valid :
                           (slave_sel == SEL_LOB)  ? lob_rsp_valid  :
                           (slave_sel == SEL_NET)  ? net_rsp_valid  :
                           (slave_sel == SEL_UART) ? uart_rsp_valid :
                           (slave_sel == SEL_SYS)  ? sys_rsp_valid  :
                           (slave_sel == SEL_ERR)  ? err_rsp_valid  : 1'b0;

    assign cpu_rsp_rdata = (slave_sel == SEL_IMEM) ? imem_rsp_rdata :
                           (slave_sel == SEL_DMEM) ? dmem_rsp_rdata :
                           (slave_sel == SEL_LOB)  ? lob_rsp_rdata  :
                           (slave_sel == SEL_NET)  ? net_rsp_rdata  :
                           (slave_sel == SEL_UART) ? uart_rsp_rdata :
                           (slave_sel == SEL_SYS)  ? sys_rsp_rdata  : 32'h0;

    assign cpu_rsp_error = (slave_sel == SEL_ERR) ? err_rsp_valid : 1'b0;

endmodule
