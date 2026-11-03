`timescale 1ns/1ps
// Nexys A7 USB Host PIC presents PS/2 scan-code set 2 on F4/B2.
// Inputs are sampled in the UI clock domain; the PIC supplies the PS/2 clock.
module ps2_receiver #(
    parameter CLK_HZ = 25_000_000
) (
    input wire clk, reset_n, ps2_clk, ps2_data,
    output reg byte_valid,
    output reg [7:0] byte_data,
    output reg frame_error
);
    (* ASYNC_REG="TRUE" *) reg [2:0] clk_sync, data_sync;
    reg [7:0] clk_filter;
    reg stable_clk;
    reg [3:0] bit_index;
    reg [7:0] bits;
    reg parity_bit;
    reg [16:0] gap;
    localparam integer GAP_LIMIT = CLK_HZ/500; // 2 ms, longer than any frame bit.
    wire falling_edge = stable_clk && clk_filter==8'h00;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            clk_sync<=3'b111; data_sync<=3'b111;clk_filter<=8'hff;
            stable_clk<=1;bit_index<=0;bits<=0;parity_bit<=0;
            gap<=0;byte_valid<=0;byte_data<=0;frame_error<=0;
        end else begin
            clk_sync<={clk_sync[1:0],ps2_clk};
            data_sync<={data_sync[1:0],ps2_data};
            clk_filter<={clk_filter[6:0],clk_sync[2]};
            byte_valid<=0;frame_error<=0;
            if (clk_filter==8'hff) stable_clk<=1;
            else if (clk_filter==8'h00) stable_clk<=0;
            if (bit_index!=0) begin
                if (gap==GAP_LIMIT-1) begin
                    bit_index<=0;gap<=0;frame_error<=1;
                end else gap<=gap+1'b1;
            end else gap<=0;
            if (falling_edge) begin
                gap<=0;
                case (bit_index)
                    0: if (!data_sync[2]) bit_index<=1;
                       else frame_error<=1;
                    1,2,3,4,5,6,7,8: begin
                        bits[bit_index-1]<=data_sync[2];
                        bit_index<=bit_index+1'b1;
                    end
                    9: begin parity_bit<=data_sync[2];bit_index<=10;end
                    10: begin
                        bit_index<=0;
                        if (data_sync[2] && (^{bits,parity_bit})) begin
                            byte_data<=bits;byte_valid<=1;
                        end else frame_error<=1;
                    end
                    default: bit_index<=0;
                endcase
            end
        end
    end
endmodule

// One event per physical press, even if a keyboard repeats its make code.
// BAT (AA) and an inactivity timeout clear lost break codes on reconnect.
module ps2_key_decoder #(
    parameter CLK_HZ = 25_000_000
) (
    input wire clk, reset_n,
    input wire byte_valid,
    input wire [7:0] byte_data,
    output reg key_valid,
    output reg [7:0] key,
    output reg key_shift,
    output reg reconnect
);
    localparam [7:0] K_F1=8'h81,K_F2=8'h82,K_F3=8'h83,K_F4=8'h84,
        K_F5=8'h85,K_F6=8'h86,K_F7=8'h87,K_F8=8'h88,
        K_TAB=8'h89,K_ENTER=8'h8a,K_ESC=8'h8b,K_BS=8'h8c,
        K_DEL=8'h8d,K_LEFT=8'h8e,K_RIGHT=8'h8f,
        K_UP=8'h90,K_DOWN=8'h91,K_PGUP=8'h92,K_PGDN=8'h93;
    reg extended,break_pending;
    reg [511:0] held;
    reg [27:0] idle_cycles;
    localparam integer IDLE_LIMIT = CLK_HZ*4; // clears lost breaks; no form reset.
    wire [8:0] identity={extended,byte_data};
    wire shift_now=held[9'h012] || held[9'h059];
    function [7:0] translate;
        input ext;
        input [7:0] scan;
        begin
            translate=0;
            if (ext) begin
                case(scan)
                    8'h6b:translate=K_LEFT; 8'h74:translate=K_RIGHT;
                    8'h75:translate=K_UP;8'h72:translate=K_DOWN;
                    8'h7d:translate=K_PGUP;8'h7a:translate=K_PGDN;
                    8'h71:translate=K_DEL;8'h5a:translate=K_ENTER;
                endcase
            end else begin
                case(scan)
                    8'h05:translate=K_F1;8'h06:translate=K_F2;
                    8'h04:translate=K_F3;8'h0c:translate=K_F4;
                    8'h03:translate=K_F5;8'h0b:translate=K_F6;
                    8'h83:translate=K_F7;8'h0a:translate=K_F8;
                    8'h0d:translate=K_TAB;8'h5a:translate=K_ENTER;
                    8'h76:translate=K_ESC;8'h66:translate=K_BS;
                    8'h16:translate="1";8'h1e:translate="2";
                    8'h26:translate="3";8'h25:translate="4";
                    8'h2e:translate="5";8'h36:translate="6";
                    8'h3d:translate="7";8'h3e:translate="8";
                    8'h46:translate="9";8'h45:translate="0";
                    8'h49:translate=".";
                    // Numeric keypad make codes in scan-code set 2.
                    8'h70:translate="0";8'h69:translate="1";
                    8'h72:translate="2";8'h7a:translate="3";
                    8'h6b:translate="4";8'h73:translate="5";
                    8'h74:translate="6";8'h6c:translate="7";
                    8'h75:translate="8";8'h7d:translate="9";
                    8'h71:translate=".";
                    8'h1c:translate="A";8'h32:translate="B";
                    8'h21:translate="C";8'h23:translate="D";
                    8'h24:translate="E";8'h2b:translate="F";
                    8'h33:translate="H";8'h2c:translate="T";
                    8'h22:translate="X";8'h3c:translate="U";
                endcase
            end
        end
    endfunction
    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            extended<=0;break_pending<=0;held<=0;idle_cycles<=0;
            key_valid<=0;key<=0;key_shift<=0;reconnect<=0;
        end else begin
            key_valid<=0;reconnect<=0;
            if(byte_valid) idle_cycles<=0;
            else if(idle_cycles<IDLE_LIMIT) idle_cycles<=idle_cycles+1'b1;
            else if(idle_cycles==IDLE_LIMIT) begin
                held<=0;extended<=0;break_pending<=0;
                idle_cycles<=idle_cycles+1'b1;
            end
            if(byte_valid) begin
                if(byte_data==8'haa) begin
                    held<=0;extended<=0;break_pending<=0;reconnect<=1;
                end else if(byte_data==8'he0) extended<=1;
                else if(byte_data==8'hf0) break_pending<=1;
                else if(byte_data!=8'hfa && byte_data!=8'hfe) begin
                    extended<=0;break_pending<=0;
                    if(break_pending) held[identity]<=0;
                    else if(!held[identity]) begin
                        held[identity]<=1;
                        if(translate(extended,byte_data)!=0) begin
                            key_valid<=1;
                            key<=translate(extended,byte_data);
                            key_shift<=shift_now || (!extended && (byte_data==8'h12 || byte_data==8'h59));
                        end
                    end
                end
            end
        end
    end
endmodule
