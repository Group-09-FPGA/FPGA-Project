import re

with open("tb_pipeline.v", "r") as f:
    content = f.read()

# Remove my previous patches
content = re.sub(r'always @\(posedge clk\) begin\n\s+if \(!?reset\) begin.*?end\nend\n', '', content, flags=re.DOTALL)

# Add back the clean version
patch = """
always @(posedge clk) begin
    if (reset) begin
        $display("next_pc = %08x", DUT.fetch_pc);
        
        // Print the ALU writes to track results
        if (DUT.wb_reg_write_en && DUT.wb_dest_reg_sel == 15 && !DUT.wb_stall && !DUT.wb_mem_to_reg) begin
            $display("time:\\t%10t ,result =\\t%10d", $time, $signed(DUT.wb_result));
        end
        
        // Dynamic stop condition for ALL workloads
        if (DUT.inst_mem_read_data == 32'h00008067) begin
            $display("All instructions are Fetched");
            $display("next_pc = 00000000");
            #10 $finish;
        end
    end
end
"""

content = content.replace("endmodule", patch + "\nendmodule")
content = content.replace("endmodule\nendmodule", "endmodule")

with open("tb_pipeline.v", "w") as f:
    f.write(content)

