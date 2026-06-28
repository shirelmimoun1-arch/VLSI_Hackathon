module accelerator
(
    input  logic        clk,
    input  logic        wb_rst_i,

    input  logic [31:0] reg_a,      // packed query
    input  logic [31:0] reg_b,      // packed reference
    input  logic [31:0] reg_c,      // {ref_len[4:0], query_len[4:0]}
    input  logic [31:0] reg_d,      // command: 1 = init, 0 = compute row

    input  logic        go,
    output logic        done,
    output logic signed [31:0] reg_result
);
    //sd for signed decimal
    localparam signed [15:0] MATCH     = 16'sd2;
    localparam signed [15:0] MISMATCH  = -16'sd1;
    localparam signed [15:0] GAP_OPEN  = -16'sd4;
    localparam signed [15:0] GAP_EXT   = -16'sd1;
    localparam signed [15:0] NEG_INF   = -16'sd10000;

    typedef enum logic [2:0] {
        IDLE, // The accelerator waits until CPU writes
        INIT, // Initializes the first previous row before any row has been computed
        ROW_START, // Initialize the boundary conditions of the current DP row
        CELL, //Each clock cycle computes one DP cell
        COPY_ROW, // After finishing the row, copy current row into previous row
        FINISH // tell CPU row is done
    } state_t;

    state_t state;

    logic rst_n;
    assign rst_n = ~wb_rst_i;

    logic [31:0] query_packed;
    logic [31:0] ref_packed;

    logic [4:0] query_len;
    logic [4:0] ref_len;

    logic [4:0] i;
    logic [4:0] j;
    logic [4:0] k; // to zero the rows in INIT and to copy the rows in COPY_ROW

    // array of 17 cells of 16 bits each
    logic signed [15:0] M_prev [0:16];
    logic signed [15:0] M_curr [0:16];
    logic signed [15:0] I_prev [0:16];
    logic signed [15:0] I_curr [0:16];
    logic signed [15:0] D_curr [0:16];

    logic signed [15:0] best_score;

    // extracts a single 2-bit DNA symbol from the 
    // packed 32-bit sequence so the accelerator can compare 
    // bases and decide between MATCH and MISMATCH.
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
        max4 = max2(max2(a,b), max2(c,d));
    endfunction

    logic signed [15:0] s;
    logic signed [15:0] new_I;
    logic signed [15:0] new_D;
    logic signed [15:0] new_M;

    always_comb begin
        s     = 16'sd0;
        new_I = 16'sd0;
        new_D = 16'sd0;
        new_M = 16'sd0;

        if (state == CELL) begin
            s = (get_base(query_packed, i - 1) == get_base(ref_packed, j - 1))
                ? MATCH
                : MISMATCH;

            new_I = max2(
                M_prev[j] + GAP_OPEN,
                I_prev[j] + GAP_EXT
            );

            new_D = max2(
                M_curr[j - 1] + GAP_OPEN,
                D_curr[j - 1] + GAP_EXT
            );

            new_M = max4(
                16'sd0,
                M_prev[j - 1] + s,
                new_I,
                new_D
            );
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= IDLE;
            done       <= 1'b0;
            reg_result <= 32'sd0;
            best_score <= 16'sd0;
            i          <= 5'd1;
            j          <= 5'd0;
            k          <= 5'd0;
        end else begin
            case (state)

                IDLE: begin
                    if (go) begin
                        done <= 1'b0;

                        if (reg_d[0]) begin
                            query_packed <= reg_a;
                            ref_packed   <= reg_b;

                            query_len <= reg_c[4:0];
                            ref_len   <= reg_c[9:5];

                            best_score <= 16'sd0;
                            i <= 5'd1;
                            k <= 5'd0;

                            state <= INIT;
                        end else begin
                            state <= ROW_START;
                        end
                    end
                end

                INIT: begin
                    M_prev[k] <= 16'sd0;
                    I_prev[k] <= NEG_INF;

                    if (k == 5'd16) begin
                        reg_result <= 32'sd0;
                        state <= FINISH;
                    end else begin
                        k <= k + 5'd1;
                    end
                end

                ROW_START: begin
                    done <= 1'b0;

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

                    if (new_M > best_score)
                        best_score <= new_M;

                    if (j == ref_len) begin
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
                        i <= i + 5'd1;
                        reg_result <= {{16{best_score[15]}}, best_score};
                        state <= FINISH;
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

            endcase
        end
    end

endmodule