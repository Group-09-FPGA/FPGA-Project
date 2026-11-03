`timescale 1ns/1ps
// Keyboard-only front panel. The PS/2 decoder emits one pulse per physical
// press. The form is text-backed so invalid edits remain visible and repairable.
module keyboard_controls (
    input wire clk, reset_n,
    input wire key_valid, key_shift,
    input wire [7:0] key,
    input wire book_valid,
    input wire [31:0] price_base, price_tick,
    input wire ram_paused,
    input wire [607:0] hash_data,
    input wire [75:0] stash_data,
    input wire [46:0] slot_data,
    output reg [3:0] page,          // 0..7 pages, 8 = quote history
    output reg [2:0] action,        // A F E C X D U
    output reg side,
    output reg [2:0] focus,         // action side price qty ID new ID list
    output reg editing,
    output wire focused_valid,
    output wire [511:0] form_text,
    output wire [19:0] form_lengths,
    output wire [19:0] form_cursors,
    output wire [31:0] price,quantity,
    output wire [63:0] order_id,new_id,
    output reg [10:0] history_offset,
    output reg [9:0] hash_set,
    output reg [2:0] hash_way,
    output reg stash_selected,
    output reg [10:0] slot_addr,
    output reg [13:0] level_addr,
    output reg [10:0] free_offset,
    output reg selected_valid,scan_busy,
    output wire ram_hold,
    output reg [63:0] selected_id,
    output reg [4:0] status,
    output reg event_valid,
    output reg [255:0] event_data,
    input wire event_ready
);
    localparam [7:0] K_F1=8'h81,K_F8=8'h88,K_TAB=8'h89,K_ENTER=8'h8a,
        K_ESC=8'h8b,K_BS=8'h8c,K_DEL=8'h8d,K_LEFT=8'h8e,
        K_RIGHT=8'h8f,K_UP=8'h90,K_DOWN=8'h91,
        K_PGUP=8'h92,K_PGDN=8'h93;
    reg [127:0] field_text[0:3];
    reg [4:0] field_len[0:3],field_cursor[0:3];
    reg [127:0] saved_text;
    reg [4:0] saved_len,saved_cursor;
    reg [1:0] saved_field;
    reg [31:0] local_sequence;
    reg [2:0] scan_state,ram_wait;
    reg [2:0] validate_wait;
    reg scan_reverse;
    reg [13:0] scanned;
    reg [255:0] pending_event;
    reg [31:0] selected_qty;
    reg [12:0] selected_price_index;
    reg selected_side;
    integer i,j;
    wire [1:0] field_index=focus-3'd2;
    wire numeric_focus=page==7 && focus>=2 && focus<=5;
    wire [75:0] selected_cell=stash_selected ? stash_data :
        (hash_data >> (hash_way*76));
    wire [3:0] operation=action<2 ? 4'd1 : action<4 ? 4'd2 :
        action==4 ? 4'd3 : action==5 ? 4'd4 : 4'd5;
    wire needs_existing=operation!=1;
    wire needs_price=operation==1 || operation==5;
    wire current_target=selected_valid && selected_cell[75] &&
        selected_cell[63:0]==selected_id && selected_cell[74:64]==slot_addr &&
        slot_data[46] && slot_data[31:0]==selected_qty &&
        slot_data[44:32]==selected_price_index && slot_data[45]==selected_side;
    assign ram_hold=scan_busy || (validate_wait>=2 && needs_existing);

    wire [255:0] parsed_values;
    wire [3:0] parsed_ok,parsed_current;
    form_parser u_parser (
        .clk(clk),.reset_n(reset_n),.text(form_text),.lengths(form_lengths),
        .values(parsed_values),.ok(parsed_ok),.current(parsed_current)
    );
    wire [63:0] price64=parsed_values[63:0],qty64=parsed_values[127:64];
    wire [63:0] id64=parsed_values[191:128],new64=parsed_values[255:192];
    wire all_parsed_current=&parsed_current;
    assign price=price64[31:0];assign quantity=qty64[31:0];
    assign order_id=id64;assign new_id=new64;
    assign focused_valid=!numeric_focus ||
        (parsed_current[field_index] && parsed_ok[field_index]);
    assign form_text={field_text[3],field_text[2],field_text[1],field_text[0]};
    assign form_lengths={field_len[3],field_len[2],field_len[1],field_len[0]};
    assign form_cursors={field_cursor[3],field_cursor[2],field_cursor[1],field_cursor[0]};
    function [7:0] hexdigit;
        input [3:0] nibble;
        begin hexdigit=nibble<10 ? "0"+nibble : "A"+nibble-10;end
    endfunction

    // Price index = (price - base) / tick, computed by a 32-cycle divider.
    reg div_start;
    reg [31:0] div_numerator,div_denominator;
    wire div_busy,div_finishing;
    wire [31:0] div_quotient;
    wire [32:0] div_remainder;
    wire dividing=div_busy || div_start;
    price_divider u_divider (
        .clk(clk),.reset_n(reset_n),.start(div_start),
        .numerator(div_numerator),.denominator(div_denominator),
        .busy(div_busy),.finishing(div_finishing),
        .quotient(div_quotient),.remainder(div_remainder)
    );

    // Selected order -> decimal text, one bit per step once the RAM data is stable.
    wire scan_go=scan_state!=0 && !ram_paused && ram_wait==3;
    wire fmt_load=scan_go && scan_state==2;
    wire fmt_step=scan_go && scan_state==3;
    wire fmt_last;
    wire [39:0] price_digits,qty_digits;
    bin_to_decimal u_price_decimal (
        .clk(clk),.reset_n(reset_n),.load(fmt_load),
        .value(price_base+slot_data[44:32]*price_tick),
        .step(fmt_step),.last(fmt_last),.digits(price_digits)
    );
    bin_to_decimal u_qty_decimal (
        .clk(clk),.reset_n(reset_n),.load(fmt_load),.value(slot_data[31:0]),
        .step(fmt_step),.last(),.digits(qty_digits)
    );

    task advance_hash;
        input backwards;
        begin
            if(!backwards) begin
                if(hash_way!=7) hash_way<=hash_way+1'b1;
                else if(stash_selected) begin stash_selected<=0;hash_way<=0;hash_set<=0;end
                else if(hash_set==1023) begin stash_selected<=1;hash_way<=0;end
                else begin hash_set<=hash_set+1'b1;hash_way<=0;end
            end else begin
                if(hash_way!=0) hash_way<=hash_way-1'b1;
                else if(stash_selected) begin stash_selected<=0;hash_set<=1023;hash_way<=7;end
                else if(hash_set==0) begin stash_selected<=1;hash_way<=7;end
                else begin hash_set<=hash_set-1'b1;hash_way<=7;end
            end
        end
    endtask

    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            page<=0;action<=0;side<=0;focus<=0;editing<=0;
            field_text[0]<="                ";field_len[0]<=0;field_cursor[0]<=0;
            field_text[1]<="                ";field_len[1]<=0;field_cursor[1]<=0;
            field_text[2]<="                ";field_len[2]<=0;field_cursor[2]<=0;
            field_text[3]<="                ";field_len[3]<=0;field_cursor[3]<=0;
            saved_text<=0;saved_len<=0;saved_cursor<=0;saved_field<=0;
            history_offset<=0;hash_set<=0;hash_way<=0;stash_selected<=0;
            slot_addr<=0;level_addr<=0;free_offset<=0;
            selected_valid<=0;scan_busy<=0;selected_id<=0;status<=0;
            selected_qty<=0;selected_price_index<=0;selected_side<=0;
            event_valid<=0;event_data<=0;local_sequence<=1;
            scan_state<=0;scan_reverse<=0;scanned<=0;ram_wait<=0;
            validate_wait<=0;
            div_start<=0;div_numerator<=0;div_denominator<=0;pending_event<=0;
        end else begin
            if(event_valid && event_ready) begin
                event_valid<=0;status<=2;local_sequence<=local_sequence+1'b1;
                if(event_data[251:248]==1) begin
                    for(j=0;j<16;j=j+1)
                        field_text[2][127-j*8-:8]<=
                            hexdigit(((id64+64'd1)>>((15-j)*4))&4'hf);
                    field_len[2]<=16;field_cursor[2]<=16;
                end
                if(event_data[251:248]==5) begin
                    for(j=0;j<16;j=j+1)
                        field_text[3][127-j*8-:8]<=
                            hexdigit(((new64+64'd1)>>((15-j)*4))&4'hf);
                    field_len[3]<=16;field_cursor[3]<=16;
                end
            end
            div_start<=0;
            if(div_finishing) begin
                if(div_remainder!=0 || div_quotient>8191) status<=5;
                else begin
                    event_data<=pending_event | ({243'd0,div_quotient[12:0]}<<67);
                    event_valid<=1;status<=1;
                end
            end
            if(scan_state!=0) begin
                if(ram_paused) ram_wait<=0;
                else if(ram_wait!=3) ram_wait<=ram_wait+1'b1;
                else if(scan_state==1) begin
                    ram_wait<=0;
                    if(selected_cell[75]) begin
                        slot_addr<=selected_cell[74:64];selected_id<=selected_cell[63:0];
                        scan_state<=2;
                    end else if(scanned==8199) begin
                        selected_valid<=0;scan_state<=0;scan_busy<=0;status<=8;
                    end else begin
                        advance_hash(scan_reverse);scanned<=scanned+1'b1;
                    end
                end else if(scan_state==2) begin
                    selected_valid<=slot_data[46];status<=0;
                    selected_qty<=slot_data[31:0];
                    selected_price_index<=slot_data[44:32];
                    selected_side<=slot_data[45];
                    scan_state<=3;
                end else begin
                    if(fmt_last) begin
                        scan_state<=0;scan_busy<=0;
                        if(selected_valid) begin
                            // Fixed width shows all stored digits and preserves
                            // exact four-place price formatting.
                            for(j=0;j<10;j=j+1) begin
                                field_text[0][127-(j+(j>=6))*8-:8] <=
                                    "0"+((price_digits>>((9-j)*4))&4'hf);
                                field_text[1][127-j*8-:8] <=
                                    "0"+((qty_digits>>((9-j)*4))&4'hf);
                            end
                            field_text[0][127-6*8-:8]<=".";
                            field_len[0]<=11;field_cursor[0]<=11;
                            field_len[1]<=10;field_cursor[1]<=10;
                            for(j=0;j<16;j=j+1)
                                field_text[2][127-j*8-:8]<=hexdigit((selected_id>>((15-j)*4))&4'hf);
                            field_len[2]<=16;field_cursor[2]<=16;
                            side<=selected_side;editing<=0;
                        end
                    end
                end
            end
            if(validate_wait!=0) begin
                if(validate_wait==1) begin
                    if(all_parsed_current) validate_wait<=needs_existing ? 2 : 6;
                end else if(ram_paused) validate_wait<=2;
                else if(validate_wait<6) validate_wait<=validate_wait+1'b1;
                else validate_wait<=0;
            end
            if(key_valid && validate_wait==0) begin
                if(key>=K_F1 && key<=K_F8) begin
                    page<=key-K_F1;focus<=0;editing<=0;history_offset<=0;
                end else if(key=="H" && !(page==7 && numeric_focus)) begin
                    page<=8;focus<=0;editing<=0;history_offset<=0;
                end else if(key>="1" && key<="8" && !numeric_focus) begin
                    page<=key-"1";focus<=0;editing<=0;history_offset<=0;
                end else if(page!=7 && key==K_TAB) begin
                    if(page==0) focus<=key_shift ? (focus==0 ? 2 : focus-1'b1) :
                                                (focus==2 ? 0 : focus+1'b1);
                    else if(page==2) focus<=!focus[0];
                    else focus<=0;
                end else if(page==7 && key==K_TAB) begin
                    if(focused_valid) begin
                        focus<=key_shift ? (focus==0 ? 6 : focus-1'b1) :
                                            (focus==6 ? 0 : focus+1'b1);
                        editing<=0;status<=0;
                    end else status<=3;
                end else if(page==7 && key==K_ESC && editing) begin
                    field_text[saved_field]<=saved_text;
                    field_len[saved_field]<=saved_len;
                    field_cursor[saved_field]<=saved_cursor;
                    editing<=0;status<=0;
                end else if(page==7 && focus==0) begin
                    if(key==K_LEFT) action<=action==0 ? 6 : action-1'b1;
                    else if(key==K_RIGHT) action<=action==6 ? 0 : action+1'b1;
                    else case(key)
                        "A":action<=0;"F":action<=1;"E":action<=2;
                        "C":action<=3;"X":action<=4;"D":action<=5;
                        "U":action<=6;
                    endcase
                end else if(page==7 && focus==1) begin
                    if(action<2 && (key==K_LEFT || key==K_RIGHT)) side<=!side;
                end else if(numeric_focus && key!=K_ENTER) begin
                    if(key==K_LEFT && field_cursor[field_index]!=0)
                        field_cursor[field_index]<=field_cursor[field_index]-1'b1;
                    else if(key==K_RIGHT && field_cursor[field_index]<field_len[field_index])
                        field_cursor[field_index]<=field_cursor[field_index]+1'b1;
                    else if(key==K_BS || key==K_DEL) begin
                        if(!editing) begin
                            saved_field<=field_index;saved_text<=field_text[field_index];
                            saved_len<=field_len[field_index];saved_cursor<=field_cursor[field_index];
                            editing<=1;
                        end
                        if(field_len[field_index]!=0 &&
                           (key==K_DEL ? field_cursor[field_index]<field_len[field_index] : field_cursor[field_index]!=0)) begin
                            if(key==K_BS) field_cursor[field_index]<=field_cursor[field_index]-1'b1;
                            for(i=0;i<15;i=i+1)
                                if(i>=(key==K_DEL ? field_cursor[field_index] : field_cursor[field_index]-1'b1))
                                    field_text[field_index][127-i*8-:8]<=field_text[field_index][119-i*8-:8];
                            field_text[field_index][7:0]<=" ";
                            field_len[field_index]<=field_len[field_index]-1'b1;
                        end
                    end else if((key>="0" && key<="9") ||
                                (field_index>=2 && key>="A" && key<="F") ||
                                (field_index==0 && key==".")) begin
                        if(!editing) begin
                            saved_field<=field_index;saved_text<=field_text[field_index];
                            saved_len<=field_len[field_index];saved_cursor<=field_cursor[field_index];
                            editing<=1;
                            field_text[field_index]<={key,{15{8'h20}}};
                            field_len[field_index]<=1;field_cursor[field_index]<=1;
                        end else if(field_len[field_index]<16) begin
                            for(i=15;i>0;i=i-1)
                                if(i>field_cursor[field_index] && i<=field_len[field_index])
                                    field_text[field_index][127-i*8-:8]<=field_text[field_index][135-i*8-:8];
                            field_text[field_index][127-field_cursor[field_index]*8-:8]<=key;
                            field_len[field_index]<=field_len[field_index]+1'b1;
                            field_cursor[field_index]<=field_cursor[field_index]+1'b1;
                        end else status<=3;
                    end
                end else if((page==1 || (page==7 && focus==6)) &&
                            (key==K_UP || key==K_DOWN) && scan_state==0) begin
                    scan_reverse<=key==K_UP;advance_hash(key==K_UP);
                    scan_state<=1;scan_busy<=1;ram_wait<=0;scanned<=0;selected_valid<=0;
                end else if(page==1 && key==K_ENTER && selected_valid) begin
                    page<=7;focus<=6;editing<=0;status<=0;
                end else if(page==0 && focus==2 && key==K_ENTER) begin
                    page<=8;focus<=0;history_offset<=0;
                end else if(key==K_PGUP) begin
                    if(page==8) history_offset<=history_offset>38 ? history_offset-38 : 0;
                    else if(page==3 || page==1 || page==0)
                        history_offset<=history_offset>36 ? history_offset-36 : 0;
                    else if(page==2) hash_set<=hash_set>8 ? hash_set-8 : 0;
                    else if(page==5) level_addr<=level_addr>36 ? level_addr-36 : 0;
                    else if(page==6) slot_addr<=slot_addr>36 ? slot_addr-36 : 0;
                end else if(key==K_PGDN) begin
                    if(page==8) history_offset<=history_offset<90 ? history_offset+11'd38 : 127;
                    else if(page==3) history_offset<=history_offset<220 ? history_offset+11'd36 : 255;
                    else if(page==1) history_offset<=history_offset<2012 ? history_offset+11'd36 : 2047;
                    else if(page==0) history_offset<=history_offset<92 ? history_offset+11'd36 : 127;
                    else if(page==2) hash_set<=hash_set<1016 ? hash_set+10'd8 : 1023;
                    else if(page==5) level_addr<=level_addr<8155 ? level_addr+14'd36 : 8191;
                    else if(page==6) slot_addr<=slot_addr<2012 ? slot_addr+11'd36 : 2047;
                end else if(page==8 || page==3 || page==0) begin
                    if(key==K_UP && history_offset<(page==3 ? 255 : 127))
                        history_offset<=history_offset+1'b1;
                    else if(key==K_DOWN && history_offset!=0) history_offset<=history_offset-1'b1;
                end else if(page==2) begin
                    if(key==K_LEFT && hash_way!=0) hash_way<=hash_way-1'b1;
                    else if(key==K_RIGHT && hash_way!=7) hash_way<=hash_way+1'b1;
                    else if(key==K_UP && hash_set!=0) hash_set<=hash_set-1'b1;
                    else if(key==K_DOWN && hash_set!=1023) hash_set<=hash_set+1'b1;
                end else if(page==5) begin
                    if(key==K_UP && level_addr!=0) level_addr<=level_addr-1'b1;
                    else if(key==K_DOWN && level_addr!=8191) level_addr<=level_addr+1'b1;
                end else if(page==6) begin
                    if(key==K_UP && slot_addr!=0) slot_addr<=slot_addr-1'b1;
                    else if(key==K_DOWN && slot_addr!=2047) slot_addr<=slot_addr+1'b1;
                end
            end
            if(key_valid && validate_wait==0 && page==7 && key==K_ENTER &&
               !event_valid && !dividing && scan_state==0)
                validate_wait<=1;
            if(validate_wait==6 && !ram_paused) begin
                if(ram_paused) status<=4;
                else if(!book_valid) status<=10;
                else if(!parsed_ok[0] && needs_price) status<=5;
                else if(!parsed_ok[1] && operation!=4) status<=6;
                else if(!parsed_ok[2]) status<=7;
                else if(operation==5 && (!parsed_ok[3] || new64==id64)) status<=7;
                else if(needs_existing && (!current_target || id64!=selected_id)) status<=8;
                else if((operation==2 || operation==3) && qty64>slot_data[31:0]) status<=11;
                else if(needs_price && (price64<price_base || price_tick==0)) status<=5;
                else begin
                    pending_event<={4'd1,operation,operation==1 && side,7'd0,
                        id64,operation==5 ? new64 : 64'd0,
                        operation==4 ? 32'd0 : qty64[31:0],13'd0,1'b0,2'd0,local_sequence,32'd0};
                    if(needs_price) begin
                        div_start<=1;div_numerator<=price64[31:0]-price_base;
                        div_denominator<=price_tick;status<=1;
                    end else begin
                        event_data<={4'd1,operation,8'd0,id64,64'd0,
                            operation==4 ? 32'd0 : qty64[31:0],16'd0,local_sequence,32'd0};
                        event_valid<=1;status<=1;
                    end
                    editing<=0;
                end
            end
        end
    end
endmodule
