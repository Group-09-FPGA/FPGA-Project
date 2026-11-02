`timescale 1ns/1ps
// Text overlay for switch-selected pages. Decimal conversion is shared and
// sequential, avoiding a large divider on the pixel clock's character path.
module board_ui_text (
    input wire clk, rst_n,
    input wire [5:0] col,
    input wire [4:0] row,
    input wire [2:0] page, action, hash_way,
    input wire [1:0] field,
    input wire side, edit_mode, browse_mode, enabled, selected_valid, scan_busy, stash,
    input wire [3:0] digit,
    input wire [4:0] status,
    input wire [31:0] price, quantity, price_base, price_tick,
    input wire [63:0] order_id, new_id, selected_id,
    input wire [9:0] hash_set,
    input wire [10:0] slot_addr, free_offset,
    input wire [13:0] level_addr,
    input wire [7:0] history_offset,
    input wire [607:0] hash_data,
    input wire [75:0] stash_data,
    input wire [46:0] slot_data,
    input wire [31:0] level_qty,
    input wire [11:0] level_count,
    input wire [10:0] free_data,
    input wire [11:0] active_orders,
    input wire [393:0] event_data,
    input wire event_visible,
    input wire [31:0] rx_count, udp_count, mold_count, itch_count, fifo_count, completed,
    input wire book_valid,
    input wire [7:0] error_code,
    output reg [7:0] character,
    output wire highlight
);
    reg [39:0] bcd [0:5];
    reg [39:0] work, adjusted;
    reg [31:0] binary;
    reg [5:0] bit_count;
    reg [2:0] value_index;
    reg [31:0] source;
    integer j;
    wire [31:0] stored_price = price_base + slot_data[44:32]*price_tick;
    wire [31:0] level_price = price_base + level_addr[12:0]*price_tick;
    always @* begin
        case(value_index)
            0:source=price; 1:source=quantity;
            2:source=page==5 ? level_price : stored_price;
            3:source=slot_data[31:0]; 4:source=level_qty;
            default:source=event_data[360:329];
        endcase
        adjusted=work;
        for(j=0;j<10;j=j+1)
            if(adjusted[j*4+:4]>=5) adjusted[j*4+:4]=adjusted[j*4+:4]+3;
    end
    integer k;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            work<=0; binary<=0; bit_count<=0; value_index<=0;
            for(k=0;k<6;k=k+1) bcd[k]<=0;
        end else if(bit_count==0) begin
            binary<=source; work<=0; bit_count<=1;
        end else begin
            work<={adjusted[38:0],binary[31]}; binary<={binary[30:0],1'b0};
            if(bit_count==32) begin
                bcd[value_index]<={adjusted[38:0],binary[31]};
                value_index<=value_index==5 ? 0 : value_index+1'b1; bit_count<=0;
            end else bit_count<=bit_count+1'b1;
        end
    end
    function [7:0] hexchar;
        input [3:0] nibble;
        begin hexchar=nibble<10 ? "0"+nibble : "A"+nibble-10; end
    endfunction
    function [7:0] decchar;
        input [39:0] digits;
        input integer position;
        begin decchar="0"+((digits >> ((9-position)*4)) & 4'hF); end
    endfunction
    function [7:0] pricechar;
        input [39:0] digits;
        input integer position;
        begin
            if(position==0) pricechar="$";
            else if(position==7) pricechar=".";
            else pricechar=decchar(digits,position<7 ? position-1 : position-2);
        end
    endfunction
    reg [319:0] line;
    reg [75:0] ram_cell;
    reg [31:0] counter_value;
    always @* begin
        line={40{8'h20}};
        ram_cell=0; counter_value=0;
        if(row==1) begin
            case(page)
                0: line="FPGA ORDER BOOK / MARKET                ";
                1: line="FPGA ORDER BOOK / ORDERS                ";
                2: line="FPGA ORDER BOOK / HASH                  ";
                3: line="FPGA ORDER BOOK / EVENTS                ";
                4: line="FPGA ORDER BOOK / STATUS                ";
                5: line="FPGA ORDER BOOK / LEVELS                ";
                6: line="FPGA ORDER BOOK / SLOTS                 ";
                7: line="FPGA ORDER BOOK / ORDER ENTRY           ";
            endcase
        end else if(row==28) line="SW4:2 PAGE  000 MARKET ... 111 ENTRY    ";
        else case(page)
            1: case(row)
                3: line="ACTIVE ORDERS / RAM BROWSE              ";
                5: line="ARROWS: PREVIOUS / NEXT ACTIVE ORDER    ";
                7: line="ORDER ID HEX:                           ";
                9: line="SLOT HEX:       SIDE:                   ";
                11: line="PRICE:                                  ";
                13: line="SHARES:                                 ";
                15: line="HASH SET HEX:       WAY:                ";
                17: line="SELECTION:                              ";
                20: line="SW4:2=111 TO OPEN ORDER ENTRY           ";
                22: line="SW12=1 THERE LOADS A BROWSED ORDER      ";
                default: begin end
            endcase
            2: case(row)
                3: line="HASH TABLE 1024 SETS X 8 WAYS           ";
                4: line="SET HEX:      WAY:    SW12=1 STASH      ";
                5: line="UP/DOWN SET - LEFT/RIGHT WAY            ";
                6: line="WAY VALID ORDER ID HEX       SLOT HEX   ";
                17: line="STASH INDEX:     VALID:                 ";
                18: line="STASH ORDER ID:                         ";
                20: line="STASH SLOT HEX:                         ";
                default: begin end
            endcase
            3: case(row)
                3: line="FPGA EVENT JOURNAL / 256 RECORDS        ";
                5: line="UP/LEFT OLDER - DOWN/RIGHT NEWER        ";
                7: line="HISTORY OFFSET HEX:                     ";
                9: line="EVENT NUMBER HEX:                       ";
                11: line="OP HEX:     1 ADD 2 EXEC 3 CANCEL       ";
                12: line="            4 DELETE 5 REPLACE          ";
                14: line="ORDER ID HEX:                           ";
                16: line="NEW ORDER ID HEX:                       ";
                18: line="REQUESTED SHARES:                       ";
                21: line="RECORD:                                 ";
                default: begin end
            endcase
            4: case(row)
                3: line="LIVE FPGA PIPELINE / COUNTERS HEX       ";
                6: line="ETHERNET:                               ";
                8: line="UDP:                                    ";
                10: line="MOLD:                                   ";
                12: line="ITCH:                                   ";
                14: line="NETWORK FIFO:                           ";
                16: line="BOOK COMPLETED:                         ";
                19: line="BOOK VALID:       ERROR HEX:            ";
                22: line="BUTTON ORDERS ENTER AFTER NETWORK       ";
                23: line="PARSER VIA A SEPARATE LOCAL FIFO        ";
                default: begin end
            endcase
            5: case(row)
                3: line="PRICE RAM / ONE LEVEL                   ";
                5: line="UP/DOWN PRICE - LEFT/RIGHT SIDE         ";
                7: line="SIDE:          INDEX HEX:               ";
                9: line="PRICE:                                  ";
                11: line="TOTAL SHARES:                           ";
                13: line="ORDER COUNT HEX:                        ";
                17: line="EMPTY LEVELS HAVE ZERO QTY AND COUNT    ";
                default: begin end
            endcase
            6: case(row)
                3: line="SLOT RAM / FREE STACK                   ";
                5: line="UP/DOWN SLOT - LEFT/RIGHT FREE DEPTH    ";
                7: line="SLOT HEX:      VALID:     SIDE:         ";
                9: line="PRICE:                                  ";
                11: line="REMAINING SHARES:                       ";
                15: line="FREE STACK DEPTH HEX:                   ";
                17: line="FREE STACK SLOT HEX:                    ";
                20: line="DEPTH ZERO IS THE NEXT ALLOCATION       ";
                default: begin end
            endcase
            7: case(row)
                3: line="ACTION:     SIDE:       ENABLE:         ";
                5: line="PRICE:                                  ";
                7: line="SHARES:                                 ";
                9: line="ORDER ID HEX:                           ";
                11: line="NEW ID HEX:                             ";
                14: line="FIELD:        DIGIT FROM RIGHT HEX:     ";
                16: line="MODE:                                   ";
                18: line="STATUS:                                 ";
                21: line="SW7:5 ACTION A F E C X D U              ";
                22: line="SW9:8 PRICE SHARES ORDER-ID NEW-ID      ";
                23: line="SW10 SIDE  SW11 EDIT  SW12 BROWSE       ";
                24: line="SW13 ENABLE  CENTER SENDS NOW           ";
                26: line="EDIT: LEFT/RIGHT DIGIT UP/DOWN VALUE    ";
                default: begin end
            endcase
            default: begin end
        endcase
        character = col<40 ? line >> ((39-col)*8) : 8'h20;
        if(page==1) begin
            if(row==7 && col>=15 && col<31) character=hexchar(selected_id >> ((30-col)*4));
            if(row==9 && col>=11 && col<14) character=hexchar({1'b0,slot_addr} >> ((13-col)*4));
            if(row==9 && col==21) character=slot_data[45] ? "S" : "B";
            if(row==11 && col>=14 && col<26) character=pricechar(bcd[2],col-14);
            if(row==13 && col>=14 && col<24) character=decchar(bcd[3],col-14);
            if(row==15 && col>=14 && col<17) character=hexchar({2'b0,hash_set} >> ((16-col)*4));
            if(row==15 && col==24) character=hexchar({1'b0,hash_way});
            if(row==17 && col>=14 && col<22) character=scan_busy ? ("SCANNING" >> ((21-col)*8)) :
                selected_valid && slot_data[46] ? ("LIVE RAM" >> ((21-col)*8)) : ("NO ORDER" >> ((21-col)*8));
        end
        if(page==2) begin
            if(row==4 && col>=9 && col<12) character=hexchar({2'b0,hash_set} >> ((11-col)*4));
            if(row==4 && col==18) character=hexchar({1'b0,hash_way});
            if(row>=7 && row<15) begin
                ram_cell=hash_data >> ((row-7)*76);
                if(col==0) character=hexchar(row-7);
                if(col==5) character=ram_cell[75] ? "1" : "0";
                if(col>=10 && col<26) character=hexchar(ram_cell[63:0] >> ((25-col)*4));
                if(col>=30 && col<33) character=hexchar({1'b0,ram_cell[74:64]} >> ((32-col)*4));
            end
            if(row==17 && col==13) character=hexchar({1'b0,hash_way});
            if(row==17 && col==23) character=stash_data[75] ? "1" : "0";
            if(row==18 && col>=16 && col<32) character=hexchar(stash_data[63:0] >> ((31-col)*4));
            if(row==20 && col>=17 && col<20) character=hexchar({1'b0,stash_data[74:64]} >> ((19-col)*4));
        end
        if(page==3) begin
            if(row==7 && col>=21 && col<23) character=hexchar(history_offset >> ((22-col)*4));
            if(event_visible) begin
                if(row==9 && col>=20 && col<28) character=hexchar(event_data[393:362] >> ((27-col)*4));
                if(row==11 && col==8) character=hexchar(event_data[314:311]);
                if(row==14 && col>=16 && col<32) character=hexchar(event_data[310:247] >> ((31-col)*4));
                if(row==16 && col>=18 && col<34) character=hexchar(event_data[246:183] >> ((33-col)*4));
                if(row==18 && col>=18 && col<28) character=decchar(bcd[5],col-18);
            end
            if(row==21 && col>=9 && col<16) character=event_visible ? ("FPGA OK" >> ((15-col)*8)) : ("NO DATA" >> ((15-col)*8));
        end
        if(page==4) begin
            case(row)
                6:counter_value=rx_count; 8:counter_value=udp_count;
                10:counter_value=mold_count; 12:counter_value=itch_count;
                14:counter_value=fifo_count; 16:counter_value=completed;
                default:counter_value=0;
            endcase
            if(row>=6 && row<=16 && !row[0] && col>=20 && col<28)
                character=hexchar(counter_value >> ((27-col)*4));
            if(row==19 && col==12) character=book_valid ? "1" : "0";
            if(row==19 && col>=29 && col<31) character=hexchar(error_code >> ((30-col)*4));
        end
        if(page==5 || page==6) begin
            if(row==9 && col>=18 && col<30) character=pricechar(bcd[2],col-18);
            if(row==11 && col>=18 && col<28) character=decchar(page==5 ? bcd[4] : bcd[3],col-18);
        end
        if(page==5) begin
            if(row==7 && col==6) character=level_addr[13] ? "S" : "B";
            if(row==7 && col>=25 && col<29) character=hexchar({3'b0,level_addr[12:0]} >> ((28-col)*4));
            if(row==13 && col>=18 && col<21) character=hexchar(level_count >> ((20-col)*4));
        end
        if(page==6) begin
            if(row==7 && col>=10 && col<13) character=hexchar({1'b0,slot_addr} >> ((12-col)*4));
            if(row==7 && col==21) character=slot_data[46] ? "1" : "0";
            if(row==7 && col==31) character=slot_data[45] ? "S" : "B";
            if(row==15 && col>=23 && col<26) character=hexchar({1'b0,free_offset} >> ((25-col)*4));
            if(row==17 && col>=23 && col<26) character=free_offset < 12'd2048-active_orders ?
                hexchar({1'b0,free_data} >> ((25-col)*4)) : "-";
        end
        if(page==7) begin
            if(row==3 && col==8) begin
                case(action)
                    0:character="A"; 1:character="F"; 2:character="E"; 3:character="C";
                    4:character="X"; 5:character="D"; 6:character="U"; 7:character="-";
                endcase
            end
            if(row==3 && col==17) character=(action<2 ? side : slot_data[45]) ? "S" : "B";
            if(row==3 && action>=2 && col>=18 && col<23) character=" AUTO" >> ((22-col)*8);
            if(row==3 && col==31) character=enabled ? "1" : "0";
            if(row==5 && col>=15 && col<27) character=pricechar(bcd[0],col-15);
            if(row==7 && col>=15 && col<25) character=decchar(bcd[1],col-15);
            if(row==9 && col>=15 && col<31) character=hexchar(order_id >> ((30-col)*4));
            if(row==11 && col>=15 && col<31) character=hexchar(new_id >> ((30-col)*4));
            if(row==14 && col==7) character=hexchar({2'b0,field});
            if(row==14 && col==35) character=hexchar(digit);
            if(row==16 && col>=7 && col<13) character=browse_mode ? ("BROWSE" >> ((12-col)*8)) :
                edit_mode ? ("EDIT  " >> ((12-col)*8)) : ("VIEW  " >> ((12-col)*8));
            if(row==18 && col>=9 && col<29) begin
                case(status)
                    0:line="READY                                   ";
                    1:line="QUEUED                                  ";
                    2:line="SENT TO CORE                            ";
                    3:line="SET SW13 TO ENABLE                      ";
                    4:line="SELECT ACTION 0 TO 6                    ";
                    5:line="PRICE RANGE OR TICK                     ";
                    6:line="SHARES MUST BE NONZERO                  ";
                    7:line="BOOK INVALID RESET                      ";
                    8:line="BROWSE AN ACTIVE ORDER                  ";
                    9:line="BUSY RETRY WHEN READY                   ";
                    10:line="INVALID ORDER ID                        ";
                    11:line="SHARES EXCEED REMAINING                 ";
                    default:line="UNKNOWN STATUS                          ";
                endcase
                character=line >> ((39-(col-9))*8);
            end
            // Decimal digit 0 is the rightmost fractional price digit.
            if(edit_mode && !browse_mode && row==6 && field==0 && col==26-digit-(digit>=4)) character="^";
            if(edit_mode && !browse_mode && row==8 && field==1 && col==24-digit) character="^";
            if(edit_mode && !browse_mode && row==10 && field==2 && col==30-digit) character="^";
            if(edit_mode && !browse_mode && row==12 && field==3 && col==30-digit) character="^";
        end
    end
    assign highlight = page==7 && ((row==5+field*2) || row==18);
endmodule
