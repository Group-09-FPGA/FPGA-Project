`timescale 1ns/1ps
// VGA-clock user interface. Buttons are synchronized, debounced and edge-only.
// btn[4:0] = {center, up, down, left, right}; one press submits at most once.
module board_controls #(
    parameter DEBOUNCE_CYCLES = 250000
) (
    input wire clk, rst_n,
    input wire [13:2] switches,
    input wire [4:0] buttons,
    input wire book_valid,
    input wire [31:0] price_base, price_tick,
    input wire ram_paused,
    input wire [607:0] hash_data,
    input wire [75:0] stash_data,
    input wire [46:0] slot_data,
    output wire [2:0] page, action,
    output wire [1:0] field,
    output wire side, edit_mode, browse_mode, enabled,
    output reg [3:0] digit,
    output reg [31:0] price, quantity,
    output reg [63:0] order_id, new_id,
    output reg [7:0] history_offset,
    output reg [9:0] hash_set,
    output reg [2:0] hash_way,
    output reg stash_selected,
    output reg [10:0] slot_addr,
    output reg [13:0] level_addr,
    output reg [10:0] free_offset,
    output reg selected_valid,
    output wire scan_busy,
    output reg [63:0] selected_id,
    output reg [4:0] status,
    output reg event_valid,
    output reg [255:0] event_data,
    input wire event_ready
);
    (* ASYNC_REG = "TRUE" *) reg [11:0] sw_meta, sw_sync;
    (* ASYNC_REG = "TRUE" *) reg [4:0] btn_meta, btn_sync;
    reg [4:0] btn_stable, press;
    reg [19:0] debounce [0:4];
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sw_meta <= 0; sw_sync <= 0;
            btn_meta <= 0; btn_sync <= 0; btn_stable <= 0; press <= 0;
            for (i=0; i<5; i=i+1) debounce[i] <= 0;
        end else begin
            sw_meta <= switches; sw_sync <= sw_meta;
            btn_meta <= buttons; btn_sync <= btn_meta; press <= 0;
            for (i=0; i<5; i=i+1) begin
                if (btn_sync[i] == btn_stable[i]) debounce[i] <= 0;
                else if (debounce[i] == DEBOUNCE_CYCLES-1) begin
                    btn_stable[i] <= btn_sync[i];
                    press[i] <= btn_sync[i];
                    debounce[i] <= 0;
                end else debounce[i] <= debounce[i]+1'b1;
            end
        end
    end
    assign page = sw_sync[2:0];       // physical SW4:2
    assign action = sw_sync[5:3];     // physical SW7:5, A F E C X D U
    assign field = sw_sync[7:6];      // physical SW9:8, price qty ID new-ID
    assign side = sw_sync[8];        // physical SW10, 0 buy 1 sell
    assign edit_mode = sw_sync[9];   // physical SW11
    assign browse_mode = sw_sync[10];// physical SW12
    assign enabled = sw_sync[11];    // physical SW13

    function [31:0] decimal_step;
        input [3:0] position;
        begin
            case(position)
                0:decimal_step=1; 1:decimal_step=10; 2:decimal_step=100;
                3:decimal_step=1000; 4:decimal_step=10000;
                5:decimal_step=100000; 6:decimal_step=1000000;
                7:decimal_step=10000000; 8:decimal_step=100000000;
                default:decimal_step=1000000000;
            endcase
        end
    endfunction
    wire [31:0] step = decimal_step(digit > 9 ? 4'd9 : digit);
    wire [63:0] id_step = 64'd1 << {digit,2'b00};
    wire [75:0] selected_cell = stash_selected ? stash_data :
                                         (hash_data >> (hash_way*76));
    wire [3:0] operation = action < 2 ? 4'd1 : action < 4 ? 4'd2 :
                           action == 4 ? 4'd3 : action == 5 ? 4'd4 : 4'd5;
    wire needs_price = operation == 1 || operation == 5;
    wire needs_existing = operation != 1;
    wire current_target = selected_valid && selected_cell[75] &&
        selected_cell[63:0] == order_id && selected_cell[74:64] == slot_addr && slot_data[46];
    reg [1:0] previous_field;
    reg [2:0] scan_state;
    assign scan_busy = scan_state != 0;
    reg scan_reverse;
    reg [13:0] scanned;
    reg [2:0] ram_wait;
    reg [31:0] local_sequence;
    reg dividing;
    reg [5:0] div_count;
    reg [31:0] div_q, div_tick;
    reg [32:0] div_rem;
    reg [255:0] pending_event;
    wire [32:0] shifted_rem = {div_rem[31:0], div_q[31]};
    wire div_take = shifted_rem >= {1'b0, div_tick};
    wire [32:0] next_rem = div_take ? shifted_rem-{1'b0,div_tick} : shifted_rem;
    wire [31:0] next_q = {div_q[30:0], div_take};
    // Walk the actual table, including collision stash, without a host index.
    task advance_hash;
        input backwards;
        begin
            if (!backwards) begin
                if (hash_way != 7) hash_way <= hash_way+1'b1;
                else if (stash_selected) begin stash_selected<=0; hash_way<=0; hash_set<=0; end
                else if (hash_set == 1023) begin stash_selected<=1; hash_way<=0; end
                else begin hash_set<=hash_set+1'b1; hash_way<=0; end
            end else begin
                if (hash_way != 0) hash_way <= hash_way-1'b1;
                else if (stash_selected) begin stash_selected<=0; hash_set<=1023; hash_way<=7; end
                else if (hash_set == 0) begin stash_selected<=1; hash_way<=7; end
                else begin hash_set<=hash_set-1'b1; hash_way<=7; end
            end
        end
    endtask
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            digit<=0; price<=905000; quantity<=100;
            order_id<=64'hB0000000; new_id<=64'hC0000000;
            history_offset<=0; hash_set<=0; hash_way<=0; stash_selected<=0;
            slot_addr<=0; level_addr<=0; free_offset<=0;
            selected_valid<=0; selected_id<=0; status<=0;
            event_valid<=0; event_data<=0; previous_field<=0;
            scan_state<=0; scan_reverse<=0; scanned<=0; ram_wait<=0;
            local_sequence<=1; dividing<=0; div_count<=0;
            div_q<=0; div_tick<=0; div_rem<=0; pending_event<=0;
        end else begin
            previous_field <= field;
            if (previous_field != field) digit<=0;
            if (event_valid && event_ready) begin
                event_valid<=0; status<=2;
                local_sequence<=local_sequence+1'b1;
                if (pending_event[251:248] == 1) order_id<=order_id+1'b1;
                if (pending_event[251:248] == 5) new_id<=new_id+1'b1;
            end
            if (dividing) begin
                div_q<=next_q; div_rem<=next_rem; div_count<=div_count+1'b1;
                if (div_count == 31) begin
                    dividing<=0;
                    if (next_rem != 0 || next_q > 8191) status<=5;
                    else begin
                        event_data<=pending_event | ({243'd0,next_q[12:0]} << 67);
                        event_valid<=1; status<=1;
                    end
                end
            end
            if (scan_state != 0) begin
                if (ram_paused) ram_wait<=0;
                else if (ram_wait != 3) ram_wait<=ram_wait+1'b1;
                else if (scan_state == 1) begin
                    ram_wait<=0;
                    if (selected_cell[75]) begin
                        slot_addr<=selected_cell[74:64]; selected_id<=selected_cell[63:0];
                        scan_state<=2;
                    end else if (scanned == 8199) begin
                        selected_valid<=0; status<=8; scan_state<=0;
                    end else begin
                        advance_hash(scan_reverse); scanned<=scanned+1'b1;
                    end
                end else begin
                    selected_valid<=slot_data[46]; scan_state<=0; status<=0;
                    if (page == 7 && browse_mode && slot_data[46]) begin
                        order_id<=selected_id; quantity<=slot_data[31:0];
                        price<=price_base + slot_data[44:32]*price_tick;
                    end
                end
            end else if (!event_valid && !dividing) begin
                if ((page == 1 || (page == 7 && browse_mode)) && |press[3:0]) begin
                    scan_reverse<=press[2] || press[1];
                    advance_hash(press[2] || press[1]);
                    scan_state<=1; ram_wait<=0; scanned<=0; selected_valid<=0;
                end else if (page == 7 && edit_mode) begin
                    if (press[2] && digit < (field < 2 ? 9 : 15)) digit<=digit+1'b1;
                    if (press[0] && digit != 0) digit<=digit-1'b1;
                    if (press[3] || press[1]) begin
                        case(field)
                            0: if (press[3] && price <= 32'hFFFFFFFF-step) price<=price+step;
                               else if (press[1] && price >= step) price<=price-step;
                            1: if (press[3] && quantity <= 32'hFFFFFFFF-step) quantity<=quantity+step;
                               else if (press[1] && quantity >= step) quantity<=quantity-step;
                            2: order_id<=press[3] ? order_id+id_step : order_id-id_step;
                            3: new_id<=press[3] ? new_id+id_step : new_id-id_step;
                        endcase
                    end
                end else if (|press[3:0]) begin
                    case(page)
                        0,3: if (press[3] || press[2]) begin
                                 if (history_offset != 255) history_offset<=history_offset+1'b1;
                             end else if (history_offset != 0) history_offset<=history_offset-1'b1;
                        2: begin
                            if (press[3] || press[1]) hash_set<=press[3] ? hash_set+1'b1 : hash_set-1'b1;
                            if (press[0] || press[2]) hash_way<=press[0] ? hash_way+1'b1 : hash_way-1'b1;
                            stash_selected<=browse_mode; selected_valid<=0;
                        end
                        5: begin
                            if (press[3] || press[1]) level_addr[12:0]<=press[3] ? level_addr[12:0]+1'b1 : level_addr[12:0]-1'b1;
                            if (press[0] || press[2]) level_addr[13]<=!level_addr[13];
                        end
                        6: begin
                            if (press[3] || press[1]) slot_addr <= press[3] ? slot_addr+1'b1 : slot_addr-1'b1;
                            if (press[0] || press[2]) free_offset <= press[0] ? free_offset+1'b1 : free_offset-1'b1;
                            selected_valid<=0;
                        end
                        default: begin end
                    endcase
                end
                if (press[4] && page == 7) begin
                    if (!enabled) status<=3;
                    else if (!book_valid) status<=7;
                    else if (action == 7) status<=4;
                    else if (ram_paused || scan_state != 0) status<=9;
                    else if (order_id == 0 || (operation == 5 && (new_id == 0 || new_id == order_id))) status<=10;
                    else if (needs_existing && !current_target) status<=8;
                    else if (operation != 4 && quantity == 0) status<=6;
                    else if ((operation == 2 || operation == 3) && quantity > slot_data[31:0]) status<=11;
                    else if (needs_price && (price < price_base || price_tick == 0)) status<=5;
                    else begin
                        pending_event <= {4'd1,operation,operation == 1 && side,7'd0,
                            order_id,operation == 5 ? new_id : 64'd0,
                            operation == 4 ? 32'd0 : quantity,13'd0,1'b0,2'd0,local_sequence,32'd0};
                        if (needs_price) begin
                            dividing<=1; div_count<=0; div_rem<=0;
                            div_q<=price-price_base; div_tick<=price_tick; status<=1;
                        end else begin
                            event_data <= {4'd1,operation,8'd0,order_id,64'd0,
                                operation == 4 ? 32'd0 : quantity,16'd0,local_sequence,32'd0};
                            event_valid<=1; status<=1;
                        end
                    end
                end
            end else if (press[4] && page == 7) status<=9;
        end
    end
endmodule
