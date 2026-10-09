/*
 * Optimized Smith-Waterman Accelerator
 *
 * Improvements over accelerator.sv:
 * - Reduced FSM from 6 states to 3 states (IDLE, CELL, FINISH)
 * - Removed explicit INIT state using implicit boundary conditions
 * - Removed ROW_START state using boundary handling in CELL
 * - Removed COPY_ROW state using ping-pong row buffers
 * - Eliminates unnecessary initialization and row-copy cycles
 */

module accelerator
(
    input  logic        clk,
    input  logic        wb_rst_i,

    input  logic [31:0] reg_a, // packed query
    input  logic [31:0] reg_b, // packed reference
    input  logic [31:0] reg_c, // lengths
    input  logic [31:0] reg_d, // command

    input  logic        go,
    output logic        done,
    output logic signed [31:0] reg_result
);

    localparam signed [15:0] MATCH     =  16'sd2;
    localparam signed [15:0] MISMATCH  = -16'sd1;
    localparam signed [15:0] GAP_OPEN  = -16'sd4;
    localparam signed [15:0] GAP_EXT   = -16'sd1;
    localparam signed [15:0] NEG_INF   = -16'sd10000;


    // ============================================================
    // FSM - only 3 states
    // ============================================================

    typedef enum logic [1:0] {
        IDLE,
        CELL,
        FINISH
    } state_t;

    state_t state;


    // ============================================================
    // Reset
    // ============================================================

    logic rst_n;
    assign rst_n = ~wb_rst_i;


    // ============================================================
    // Input registers
    // ============================================================

    logic [31:0] query_packed;
    logic [31:0] ref_packed;

    logic [4:0] query_len;
    logic [4:0] ref_len;

    // i = row
    // j = column
    logic [4:0] i;
    logic [4:0] j;


    // ============================================================
    // Ping-pong row buffers
    //
    // Instead of:
    //
    //     M_prev
    //     M_curr
    //
    // we have two physical banks.
    //
    // curr_bank tells us which bank is currently being written.
    // The other bank contains the previous row.
    // ============================================================

    logic signed [15:0] M_bank0 [0:16];
    logic signed [15:0] M_bank1 [0:16];

    logic signed [15:0] I_bank0 [0:16];
    logic signed [15:0] I_bank1 [0:16];

    logic curr_bank;


    // D only depends on the previous cell in the SAME row.
    // Therefore we don't need two D banks.
    logic signed [15:0] D_curr [0:16];


    // ============================================================
    // Score
    // ============================================================

    logic signed [15:0] best_score;
    logic signed [15:0] max_possible_score;


    // Maximum possible score:
    //
    // min(query_len, ref_len) * MATCH
    //
    // MATCH = 2, so multiplying by 2 is equivalent to << 1.
    always_comb begin
        if (query_len < ref_len)
            max_possible_score =
                $signed({10'd0, query_len, 1'b0});
        else
            max_possible_score =
                $signed({10'd0, ref_len, 1'b0});
    end


    // ============================================================
    // Helper functions
    // ============================================================

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


    // ============================================================
    // CELL datapath
    // ============================================================

    logic signed [15:0] s;

    logic signed [15:0] prev_M;
    logic signed [15:0] prev_I;
    logic signed [15:0] prev_diag_M;

    logic signed [15:0] left_M;
    logic signed [15:0] left_D;

    logic signed [15:0] new_I;
    logic signed [15:0] new_D;
    logic signed [15:0] new_M;

    logic signed [15:0] best_next;


    always_comb begin

        // Defaults
        s           = 16'sd0;

        prev_M      = 16'sd0;
        prev_I      = NEG_INF;
        prev_diag_M = 16'sd0;

        left_M      = 16'sd0;
        left_D      = NEG_INF;

        new_I       = 16'sd0;
        new_D       = 16'sd0;
        new_M       = 16'sd0;

        best_next   = best_score;


        if (state == CELL) begin

            // ====================================================
            // Match / mismatch score
            // ====================================================

            s = (
                get_base(query_packed, i - 5'd1) ==
                get_base(ref_packed,   j - 5'd1)
            )
                ? MATCH
                : MISMATCH;


            // ====================================================
            // TOP BOUNDARY
            //
            // Original INIT created:
            //
            // M row 0 = 0
            // I row 0 = -INF
            //
            // We no longer physically create that row.
            //
            // If i == 1, pretend that previous row contains
            // those boundary values.
            // ====================================================

            if (i == 5'd1) begin

                prev_M      = 16'sd0;
                prev_I      = NEG_INF;
                prev_diag_M = 16'sd0;

            end else begin

                // Previous row is in the opposite bank
                // from the current row.

                if (curr_bank == 1'b0) begin

                    // bank0 = current
                    // bank1 = previous

                    prev_M      = M_bank1[j];
                    prev_I      = I_bank1[j];

                    // For column 1, diagonal points to column 0,
                    // whose M boundary value is 0.
                    if (j == 5'd1)
                        prev_diag_M = 16'sd0;
                    else
                        prev_diag_M = M_bank1[j - 5'd1];

                end else begin

                    // bank1 = current
                    // bank0 = previous

                    prev_M      = M_bank0[j];
                    prev_I      = I_bank0[j];

                    if (j == 5'd1)
                        prev_diag_M = 16'sd0;
                    else
                        prev_diag_M = M_bank0[j - 5'd1];

                end
            end


            // ====================================================
            // LEFT BOUNDARY
            //
            // Original ROW_START created:
            //
            // M_curr[0] = 0
            // D_curr[0] = -INF
            //
            // We no longer physically write those values.
            //
            // If j == 1, simply use the known boundary values.
            // ====================================================

            if (j == 5'd1) begin

                left_M = 16'sd0;
                left_D = NEG_INF;

            end else begin

                if (curr_bank == 1'b0)
                    left_M = M_bank0[j - 5'd1];
                else
                    left_M = M_bank1[j - 5'd1];

                left_D = D_curr[j - 5'd1];
            end


            // ====================================================
            // Smith-Waterman recurrence
            // ====================================================

            new_I = max2(
                prev_M + GAP_OPEN,
                prev_I + GAP_EXT
            );


            new_D = max2(
                left_M + GAP_OPEN,
                left_D + GAP_EXT
            );


            new_M = max4(
                16'sd0,
                prev_diag_M + s,
                new_I,
                new_D
            );


            best_next = max2(
                best_score,
                new_M
            );

        end
    end


    // ============================================================
    // FSM
    // ============================================================

    always_ff @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            state      <= IDLE;

            done       <= 1'b0;
            reg_result <= 32'sd0;

            best_score <= 16'sd0;

            query_len  <= 5'd0;
            ref_len    <= 5'd0;

            i          <= 5'd1;
            j          <= 5'd1;

            curr_bank  <= 1'b0;

        end else begin

            case (state)


                // =================================================
                // IDLE
                // =================================================

                IDLE: begin

                    done <= 1'b0;

                    if (go && reg_d[0]) begin

                        query_packed <= reg_a;
                        ref_packed   <= reg_b;

                        query_len <= reg_c[4:0];
                        ref_len   <= reg_c[9:5];

                        best_score <= 16'sd0;
                        reg_result <= 32'sd0;

                        // Start directly at cell (1,1)
                        i <= 5'd1;
                        j <= 5'd1;

                        // Arbitrarily use bank0 for the first row.
                        // There is no real previous bank for row 1
                        // because the top boundary is generated
                        // directly in the CELL logic.
                        curr_bank <= 1'b0;

                        state <= CELL;
                    end
                end


                // =================================================
                // CELL
                // =================================================

                CELL: begin

                    // Store the newly calculated cell
                    // in the current bank.

                    if (curr_bank == 1'b0) begin
                        M_bank0[j] <= new_M;
                        I_bank0[j] <= new_I;
                    end else begin
                        M_bank1[j] <= new_M;
                        I_bank1[j] <= new_I;
                    end

                    D_curr[j] <= new_D;

                    best_score <= best_next;


                    // =============================================
                    // Early termination
                    // =============================================

                    if (best_next >= max_possible_score) begin

                        reg_result <= {
                            {16{best_next[15]}},
                            best_next
                        };

                        state <= FINISH;


                    // =============================================
                    // End of current row
                    // =============================================

                    end else if (j == ref_len) begin


                        // -----------------------------------------
                        // Last row -> entire matrix finished
                        // -----------------------------------------

                        if (i == query_len) begin

                            // Important:
                            // use best_next, not best_score,
                            // because best_score is updated on this
                            // same clock edge.

                            reg_result <= {
                                {16{best_next[15]}},
                                best_next
                            };

                            state <= FINISH;


                        // -----------------------------------------
                        // More rows remain
                        // -----------------------------------------

                        end else begin

                            i <= i + 5'd1;

                            // Start next row directly at column 1.
                            // No ROW_START state required.
                            j <= 5'd1;

                            // Swap the roles of the banks.
                            //
                            // The bank we just wrote becomes
                            // the previous-row bank.
                            //
                            // The other bank becomes the new
                            // current-row bank.
                            curr_bank <= ~curr_bank;

                        end


                    // =============================================
                    // Continue current row
                    // =============================================

                    end else begin

                        j <= j + 5'd1;

                    end
                end


                // =================================================
                // FINISH
                // =================================================

                FINISH: begin

                    done <= 1'b1;

                    // Wait for software to clear GO.
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
