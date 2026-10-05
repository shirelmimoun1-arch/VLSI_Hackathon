module accelerator
(
    input  logic        clk,
    input  logic        wb_rst_i,

    input  logic [31:0] reg_a, // packed query (4 bytes, 32 bits)
    input  logic [31:0] reg_b, // packed reference
    input  logic [31:0] reg_c, // lengths
    input  logic [31:0] reg_d, // command

    input  logic        go, // start
    output logic        done,
    output logic signed [31:0] reg_result // best alignment score
);

    // sd for signed decimal, localparam for a compile-time constant
    localparam signed [15:0] MATCH     = 16'sd2;
    localparam signed [15:0] MISMATCH  = -16'sd1;
    localparam signed [15:0] GAP_OPEN  = -16'sd4;
    localparam signed [15:0] GAP_EXT   = -16'sd1;
    localparam signed [15:0] NEG_INF   = -16'sd10000;

    typedef enum logic [2:0] {
        IDLE,      // wait for go
        INIT,      // initialize row 0
        ROW_START, // initialize new row
        CELL,      // compute one DP cell
        COPY_ROW,  // move current row to previous row
        FINISH     // raise done
    } state_t;

    state_t state;

    logic rst_n;
    assign rst_n = ~wb_rst_i;

    logic [31:0] query_packed;
    logic [31:0] ref_packed;

    logic [4:0] query_len;
    logic [4:0] ref_len;

   // i for row
   // j for column
   // k for initialization/copy index
    logic [4:0] i, j, k;

    // Instead of full 16×16 matrices, hardware stores the
    // relevant rows for the computation
    logic signed [15:0] M_prev [0:16];
    logic signed [15:0] M_curr [0:16];
    logic signed [15:0] I_prev [0:16];
    logic signed [15:0] I_curr [0:16];
    logic signed [15:0] D_curr [0:16];

    logic signed [15:0] best_score;
    logic signed [15:0] max_possible_score;

    // The maximum possible Smith-Waterman score is min(query_len, ref_len) × MATCH.
    // Once this score is reached, the accelerator can safely terminate early.
    always_comb begin
        if (query_len < ref_len)
            max_possible_score = $signed({10'd0, query_len, 1'b0});
        else
            max_possible_score = $signed({10'd0, ref_len, 1'b0});
    end

    // extracts 2 bits from the packed DNA
    function automatic logic [1:0] get_base(
        input logic [31:0] dna_word,
        input logic [4:0] idx
    );
        get_base = (dna_word >> (2 * idx)) & 2'b11;
    endfunction

    function automatic signed [15:0] max2(
        input signed [15:0] a,
        input signed [15:0] b
    );
        max2 = (a > b) ? a : b;
    endfunction

    function automatic signed [15:0] max4(
        input signed [15:0] a,
        input signed [15:0] b,
        input signed [15:0] c,
        input signed [15:0] d
    );
        max4 = max2(max2(a, b), max2(c, d));
    endfunction

    logic signed [15:0] s;
    logic signed [15:0] new_I;
    logic signed [15:0] new_D;
    logic signed [15:0] new_M;
    logic signed [15:0] best_next;

    // FSM- CELL state
    always_comb begin
        s         = 16'sd0;
        new_I     = 16'sd0;
        new_D     = 16'sd0;
        new_M     = 16'sd0;
        best_next = best_score;

        if (state == CELL) begin
            s = (get_base(query_packed, i - 5'd1) == get_base(ref_packed, j - 5'd1))
                ? MATCH
                : MISMATCH;

            new_I = max2(
                M_prev[j] + GAP_OPEN,
                I_prev[j] + GAP_EXT
            );

            new_D = max2(
                M_curr[j - 5'd1] + GAP_OPEN,
                D_curr[j - 5'd1] + GAP_EXT
            );

            new_M = max4(
                16'sd0,
                M_prev[j - 5'd1] + s,
                new_I,
                new_D
            );

            best_next = max2(best_score, new_M);
        end
    end

    // FSM
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= IDLE;
            done       <= 1'b0;
            reg_result <= 32'sd0;
            best_score <= 16'sd0;
            query_len  <= 5'd0;
            ref_len    <= 5'd0;
            i          <= 5'd1;
            j          <= 5'd0;
            k          <= 5'd0;
        end else begin
            case (state)

                IDLE: begin
                    done <= 1'b0;

                    if (go && reg_d[0]) begin
                        query_packed <= reg_a;
                        ref_packed   <= reg_b;

                        query_len <= reg_c[4:0];
                        ref_len   <= reg_c[9:5];

                        best_score <= 16'sd0;
                        reg_result <= 32'sd0;

                        i <= 5'd1;
                        k <= 5'd0;

                        state <= INIT;
                    end
                end

                INIT: begin
                    M_prev[k] <= 16'sd0;
                    I_prev[k] <= NEG_INF;

                    if (k == 5'd16) begin
                        k <= 5'd0;
                        state <= ROW_START;
                    end else begin
                        k <= k + 5'd1;
                    end
                end

                ROW_START: begin
                    M_curr[0] <= 16'sd0;
                    I_curr[0] <= NEG_INF;
                    D_curr[0] <= NEG_INF;

                    j <= 5'd1;
                    state <= CELL;
                end

                CELL: begin
                    I_curr[j] <= new_I;
                    D_curr[j] <= new_D;
                    M_curr[j] <= new_M;
                    best_score <= best_next;

                    if (best_next >= max_possible_score) begin
                        reg_result <= {{16{best_next[15]}}, best_next};
                        state <= FINISH;
                    end else if (j == ref_len) begin
                        k <= 5'd0;
                        state <= COPY_ROW;
                    end else begin
                        j <= j + 5'd1;
                    end
                end

                COPY_ROW: begin
                    M_prev[k] <= M_curr[k];
                    I_prev[k] <= I_curr[k];

                    if (k == ref_len) begin
                        if (i == query_len) begin
                            reg_result <= {{16{best_score[15]}}, best_score};
                            state <= FINISH;
                        end else begin
                            i <= i + 5'd1;
                            k <= 5'd0;
                            state <= ROW_START;
                        end
                    end else begin
                        k <= k + 5'd1;
                    end
                end

                FINISH: begin
                    done <= 1'b1;

                    if (!go) begin
                        state <= IDLE;
                    end
                end

                default: begin
                    state <= IDLE;
                end

            endcase
        end
    end

endmodule
