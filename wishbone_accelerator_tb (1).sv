`timescale 1ns/1ps

module accelerator_tb;

    logic clk;
    logic wb_rst_i;

    logic [31:0] reg_a;
    logic [31:0] reg_b;
    logic [31:0] reg_c;
    logic [31:0] reg_d;
    logic go;
    logic done;
    logic signed [31:0] reg_result;

    accelerator dut (
        .clk(clk),
        .wb_rst_i(wb_rst_i),
        .reg_a(reg_a),
        .reg_b(reg_b),
        .reg_c(reg_c),
        .reg_d(reg_d),
        .go(go),
        .done(done),
        .reg_result(reg_result)
    );

    always #5 clk = ~clk;

    task do_go;
    begin
        go = 1'b1;
        @(posedge clk);
        go = 1'b0;
        wait(done == 1'b1);
        @(posedge clk);
    end
    endtask

    task run_test;
        input [31:0] packed_ref;
        input [31:0] packed_query;
        input [4:0]  ref_len;
        input [4:0]  query_len;
        input integer expected;
        integer row;
    begin
        reg_a = packed_query;
        reg_b = packed_ref;
        reg_c = {22'd0, ref_len, query_len};
        reg_d = 32'd1; // INIT
        do_go();

        for(row = 0; row < query_len; row = row + 1) begin
            reg_d = 32'd0; // compute one row
            do_go();
        end

        if(reg_result == expected)
            $display("PASSED: result=%0d expected=%0d", reg_result, expected);
        else
            $display("FAILED: result=%0d expected=%0d", reg_result, expected);
    end
    endtask

    initial begin
        clk = 1'b0;
        wb_rst_i = 1'b1;
        go = 1'b0;
        reg_a = 32'd0;
        reg_b = 32'd0;
        reg_c = 32'd0;
        reg_d = 32'd0;

        repeat(5) @(posedge clk);
        wb_rst_i = 1'b0;
        repeat(2) @(posedge clk);

        // A=00, C=01, G=10, T=11
        // Query: ACGTCGTACGTACGTA
        // packed_query = pack_dna("ACGTCGTACGTACGTA")
        // Reference 0: ACGTACGTACGTACGT
        run_test(
            32'hE4E4E4E4,
            32'h38E4E4E4,
            5'd16,
            5'd16,
            26
        );

        // Reference 3: TTTTTTTTTTTTTTTT
        run_test(
            32'hFFFFFFFF,
            32'h38E4E4E4,
            5'd16,
            5'd16,
            2
        );

        $finish;
    end

endmodule