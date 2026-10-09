`timescale 1ns/1ps

module rv32m_unit (
    input  wire        clk,
    input  wire        reset,          // Active-low asynchronous reset
    input  wire        start,          // 1-cycle initiation strobe from EX stage
    input  wire [2:0]  funct3,         // Operation select
    input  wire [31:0] op1,            // Forwarded operand 1 (rs1)
    input  wire [31:0] op2,            // Forwarded operand 2 (rs2)
    input  wire        stall_pipeline, // Pipeline stall status
    output wire        busy,           // Unit is currently calculating
    output wire        done,           // Result is valid
    output wire [31:0] result          // Architectural result
);

    // --------------------------------------------------------
    // OPERATION ENCODINGS
    // --------------------------------------------------------
    localparam F3_MUL    = 3'b000;
    localparam F3_MULH   = 3'b001;
    localparam F3_MULHSU = 3'b010;
    localparam F3_MULHU  = 3'b011;
    localparam F3_DIV    = 3'b100;
    localparam F3_DIVU   = 3'b101;
    localparam F3_REM    = 3'b110;
    localparam F3_REMU   = 3'b111;

    // --------------------------------------------------------
    // FSM STATES
    // --------------------------------------------------------
    localparam STATE_IDLE = 2'b00;
    localparam STATE_MULT = 2'b01;
    localparam STATE_DIV  = 2'b10;
    localparam STATE_DONE = 2'b11;

    reg [1:0] state;

    // --------------------------------------------------------
    // MULTIPLIER (3-STAGE PIPELINED)
    // --------------------------------------------------------
    // Operand extension to 33 bits signed
    wire sign_a = (funct3 == F3_MULH) || (funct3 == F3_MULHSU);
    wire sign_b = (funct3 == F3_MULH);

    wire [32:0] ext_a = sign_a ? {op1[31], op1} : {1'b0, op1};
    wire [32:0] ext_b = sign_b ? {op2[31], op2} : {1'b0, op2};

    // Stage 1 registers
    reg signed [32:0] mult_reg_a;
    reg signed [32:0] mult_reg_b;
    reg [2:0]         mult_op_r1;

    // Stage 2 registers
    reg signed [65:0] mult_prod_r2;
    reg [2:0]         mult_op_r2;

    reg [1:0] mult_cnt;

    // --------------------------------------------------------
    // DIVIDER (32-ITERATION RESTORING)
    // --------------------------------------------------------
    wire op1_is_signed = (funct3 == F3_DIV) || (funct3 == F3_REM);
    wire op2_is_signed = (funct3 == F3_DIV) || (funct3 == F3_REM);

    wire op1_neg = op1_is_signed && op1[31];
    wire op2_neg = op2_is_signed && op2[31];

    wire [31:0] abs_op1 = op1_neg ? (-op1) : op1;
    wire [31:0] abs_op2 = op2_neg ? (-op2) : op2;

    reg [31:0] rem_reg;
    reg [31:0] quo_reg;
    reg [31:0] div_reg;
    reg [4:0]  div_cnt;
    reg [2:0]  div_op_r;
    reg [31:0] orig_op1;
    reg        neg_quo;
    reg        neg_rem;
    reg        div_zero;
    reg        overflow;

    // Restoring iteration recurrence
    wire [32:0] shifted_rem = {rem_reg[31:0], quo_reg[31]};
    wire [33:0] trial_sub   = {1'b0, shifted_rem} - {2'b0, div_reg};
    wire        borrow      = trial_sub[33];
    wire [31:0] next_rem    = borrow ? shifted_rem[31:0] : trial_sub[31:0];
    wire [31:0] next_quo    = {quo_reg[30:0], ~borrow};

    // Final-iteration quotient and remainder correction at cnt == 31
    wire [31:0] final_quo_u = next_quo;
    wire [31:0] final_rem_u = next_rem;
    wire [31:0] final_quo   = neg_quo ? (-final_quo_u) : final_quo_u;
    wire [31:0] final_rem   = neg_rem ? (-final_rem_u) : final_rem_u;

    reg [31:0] final_div_result;
    always @(*) begin
        if (div_zero) begin
            case (div_op_r)
                F3_DIV : final_div_result = 32'hFFFF_FFFF;
                F3_DIVU: final_div_result = 32'hFFFF_FFFF;
                F3_REM : final_div_result = orig_op1;
                F3_REMU: final_div_result = orig_op1;
                default: final_div_result = 32'hFFFF_FFFF;
            endcase
        end else if (overflow) begin
            case (div_op_r)
                F3_DIV : final_div_result = 32'h8000_0000;
                F3_REM : final_div_result = 32'h0000_0000;
                default: final_div_result = 32'h0000_0000;
            endcase
        end else begin
            case (div_op_r)
                F3_DIV : final_div_result = final_quo;
                F3_DIVU: final_div_result = final_quo_u;
                F3_REM : final_div_result = final_rem;
                F3_REMU: final_div_result = final_rem_u;
                default: final_div_result = 32'h0000_0000;
            endcase
        end
    end

    // Result register latched when computation completes
    reg [31:0] result_reg;

    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            state        <= STATE_IDLE;
            mult_reg_a   <= 33'sd0;
            mult_reg_b   <= 33'sd0;
            mult_op_r1   <= 3'd0;
            mult_prod_r2 <= 66'sd0;
            mult_op_r2   <= 3'd0;
            mult_cnt     <= 2'd0;
            rem_reg      <= 32'd0;
            quo_reg      <= 32'd0;
            div_reg      <= 32'd0;
            div_cnt      <= 5'd0;
            div_op_r     <= 3'd0;
            orig_op1     <= 32'd0;
            neg_quo      <= 1'b0;
            neg_rem      <= 1'b0;
            div_zero     <= 1'b0;
            overflow     <= 1'b0;
            result_reg   <= 32'd0;
        end else begin
            case (state)
                STATE_IDLE: begin
                    if (start) begin
                        if (!funct3[2]) begin
                            // Multiplier launch: Edge 1 captures Stage 1
                            mult_reg_a <= $signed(ext_a);
                            mult_reg_b <= $signed(ext_b);
                            mult_op_r1 <= funct3;
                            mult_cnt   <= 2'd0;
                            state      <= STATE_MULT;
                        end else begin
                            // Divider launch: Edge 1 captures Init
                            rem_reg   <= 32'd0;
                            quo_reg   <= abs_op1;
                            div_reg   <= abs_op2;
                            div_cnt   <= 5'd0;
                            div_op_r  <= funct3;
                            orig_op1  <= op1;
                            neg_quo   <= op1_is_signed && (op1[31] ^ op2[31]) && (op2 != 32'd0);
                            neg_rem   <= op1_is_signed && op1[31] && (op2 != 32'd0);
                            div_zero  <= (op2 == 32'd0);
                            overflow  <= op1_is_signed && (op1 == 32'h8000_0000) && (op2 == 32'hFFFF_FFFF);
                            state     <= STATE_DIV;
                        end
                    end
                end

                STATE_MULT: begin
                    if (mult_cnt == 2'd0) begin
                        // Edge 2: Stage 2 captures 66-bit product
                        mult_prod_r2 <= mult_reg_a * mult_reg_b;
                        mult_op_r2   <= mult_op_r1;
                        mult_cnt     <= 2'd1;
                    end else if (mult_cnt == 2'd1) begin
                        // Edge 3: Stage 3 captures formatted result, moves to DONE
                        result_reg <= (mult_op_r2 == F3_MUL) ? mult_prod_r2[31:0] : mult_prod_r2[63:32];
                        state      <= STATE_DONE;
                    end
                end

                STATE_DIV: begin
                    if (div_cnt < 5'd31) begin
                        rem_reg <= next_rem;
                        quo_reg <= next_quo;
                        div_cnt <= div_cnt + 5'd1;
                    end else begin
                        // Edge 33 (cnt == 31): Combinational 32nd iteration registered into result_reg
                        result_reg <= final_div_result;
                        state      <= STATE_DONE;
                    end
                end

                STATE_DONE: begin
                    // Hold result and done until pipeline accepts it (!stall_pipeline)
                    if (!stall_pipeline) begin
                        state <= STATE_IDLE;
                    end
                end
            endcase
        end
    end

    assign busy   = (state == STATE_MULT) || (state == STATE_DIV);
    assign done   = (state == STATE_DONE);
    assign result = result_reg;

endmodule
