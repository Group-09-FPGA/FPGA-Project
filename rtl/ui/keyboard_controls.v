`timescale 1ns/1ps
// Read-only front panel. The PS/2 decoder emits one pulse per physical press;
// keys only change which page is shown and where it is scrolled. No key can
// create, change or cancel an order.
module keyboard_controls (
    input wire clk, reset_n,
    input wire key_valid, key_shift,
    input wire [7:0] key,
    output reg [3:0] page,          // 0..3, 5, 6 pages; 8 = quote history
    output reg [2:0] focus,         // Market: 0..2
    output reg [10:0] history_offset,
    output reg [9:0] hash_set,
    output reg [2:0] hash_way,
    output reg stash_selected,
    output reg [10:0] slot_addr,
    output reg [13:0] level_addr
);
    localparam [7:0] K_F1=8'h81,K_F6=8'h86,K_TAB=8'h89,K_ENTER=8'h8a,
        K_LEFT=8'h8e,K_RIGHT=8'h8f,K_UP=8'h90,K_DOWN=8'h91,
        K_PGUP=8'h92,K_PGDN=8'h93;
    // Pages 0..3 and 5..6; page 4 (status) and 7 (order entry) no longer exist.
    wire [3:0] fkey_index=key-K_F1, digit_index=key-"1";
    wire [3:0] fkey_page=fkey_index<4 ? fkey_index : fkey_index+1'b1;
    wire [3:0] digit_page=digit_index<4 ? digit_index : digit_index+1'b1;

    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            page<=0;focus<=0;history_offset<=0;hash_set<=0;hash_way<=0;
            stash_selected<=0;slot_addr<=0;level_addr<=0;
        end else if(key_valid) begin
            if(key>=K_F1 && key<=K_F6) begin
                page<=fkey_page;focus<=0;history_offset<=0;
            end else if(key=="H") begin
                page<=8;focus<=0;history_offset<=0;
            end else if(key>="1" && key<="6") begin
                page<=digit_page;focus<=0;history_offset<=0;
            end else if(key==K_TAB) begin
                if(page==0) focus<=key_shift ? (focus==0 ? 2 : focus-1'b1) :
                                            (focus==2 ? 0 : focus+1'b1);
                else if(page==2) hash_way<=key_shift ? hash_way-1'b1 : hash_way+1'b1;
                else focus<=0;
            end else if(page==0 && focus==2 && key==K_ENTER) begin
                page<=8;focus<=0;history_offset<=0;
            end else if(key==K_PGUP) begin
                if(page==8) history_offset<=history_offset>38 ? history_offset-38 : 0;
                else if(page==3 || page==1 || page==0)
                    history_offset<=history_offset>36 ? history_offset-36 : 0;
                else if(page==2) hash_set<=hash_set>256 ? hash_set-256 : 0;
                else if(page==5) level_addr<=level_addr>256 ? level_addr-256 : 0;
                else if(page==6) slot_addr<=slot_addr>512 ? slot_addr-512 : 0;
            end else if(key==K_PGDN) begin
                if(page==8) history_offset<=history_offset<90 ? history_offset+11'd38 : 127;
                else if(page==3) history_offset<=history_offset<220 ? history_offset+11'd36 : 255;
                else if(page==1) history_offset<=history_offset<2012 ? history_offset+11'd36 : 2047;
                else if(page==0) history_offset<=history_offset<92 ? history_offset+11'd36 : 127;
                else if(page==2) hash_set<=hash_set<768 ? hash_set+10'd256 : 1023;
                else if(page==5) level_addr<=level_addr<768 ? level_addr+14'd256 : 1023;
                else if(page==6) slot_addr<=slot_addr<1536 ? slot_addr+11'd512 : 2047;
            end else if(page==8 || page==3 || page==0) begin
                if(key==K_UP && history_offset<(page==3 ? 255 : 127))
                    history_offset<=history_offset+1'b1;
                else if(key==K_DOWN && history_offset!=0) history_offset<=history_offset-1'b1;
            end else if(page==1) begin
                if(key==K_UP && history_offset!=0) history_offset<=history_offset-1'b1;
                else if(key==K_DOWN && history_offset<2047) history_offset<=history_offset+1'b1;
            end else if(page==2) begin
                // The 32x32 grid of sets: arrows move the selected square.
                if(key==K_LEFT && hash_set!=0) hash_set<=hash_set-1'b1;
                else if(key==K_RIGHT && hash_set!=1023) hash_set<=hash_set+1'b1;
                else if(key==K_UP && hash_set>=32) hash_set<=hash_set-10'd32;
                else if(key==K_DOWN && hash_set<992) hash_set<=hash_set+10'd32;
            end else if(page==5) begin
                // 32x32 grid of price-level squares (8 price steps each).
                if(key==K_LEFT && level_addr!=0) level_addr<=level_addr-1'b1;
                else if(key==K_RIGHT && level_addr!=1023) level_addr<=level_addr+1'b1;
                else if(key==K_UP && level_addr>=32) level_addr<=level_addr-14'd32;
                else if(key==K_DOWN && level_addr<992) level_addr<=level_addr+14'd32;
            end else if(page==6) begin
                // 64x32 grid of order slots.
                if(key==K_LEFT && slot_addr!=0) slot_addr<=slot_addr-1'b1;
                else if(key==K_RIGHT && slot_addr!=2047) slot_addr<=slot_addr+1'b1;
                else if(key==K_UP && slot_addr>=64) slot_addr<=slot_addr-11'd64;
                else if(key==K_DOWN && slot_addr<1984) slot_addr<=slot_addr+11'd64;
            end
        end
    end
endmodule
