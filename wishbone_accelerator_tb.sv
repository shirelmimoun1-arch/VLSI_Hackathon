`timescale 1ns/1ps

module accelerator_top_tb;

  logic        wb_clk_i;
  logic        wb_rst_i;
  logic        wb_stb_i;
  logic [2:0]  wb_cti_i;
  logic [1:0]  wb_bte_i;
  logic        wb_cyc_i;
  logic [3:0]  wb_sel_i;
  logic        wb_we_i;
  logic [7:0]  wb_adr_i;
  logic [31:0] wb_dat_i;
  logic [31:0] wb_dat_o;
  logic        wb_ack_o;
  logic        wb_err_o;
  logic        wb_rty_o;
  logic        int_o;

  accelerator_top dut (
      .wb_clk_i  (wb_clk_i),
      .wb_rst_i  (wb_rst_i),
      .wb_stb_i  (wb_stb_i),
      .wb_cti_i  (wb_cti_i),
      .wb_bte_i  (wb_bte_i),
      .wb_cyc_i  (wb_cyc_i),
      .wb_sel_i  (wb_sel_i),
      .wb_we_i   (wb_we_i),
      .wb_adr_i  (wb_adr_i),
      .wb_dat_i  (wb_dat_i),
      .wb_dat_o  (wb_dat_o),
      .wb_ack_o  (wb_ack_o),
      .wb_err_o  (wb_err_o),
      .wb_rty_o  (wb_rty_o),
      .int_o     (int_o)
  );

  localparam ACC0_BASE = 8'h00;
  localparam ACC1_BASE = 8'h20;

  localparam REG_CONTROL = 8'h00;
  localparam REG_A       = 8'h04;
  localparam REG_B       = 8'h08;
  localparam REG_C       = 8'h0C;
  localparam REG_D       = 8'h10;
  localparam REG_RESULT  = 8'h14;

  initial begin
    wb_clk_i = 1'b0;
    forever #5 wb_clk_i = ~wb_clk_i;
  end

  function automatic [1:0] encode_base(input byte c);
    case (c)
      "A": encode_base = 2'd0;
      "C": encode_base = 2'd1;
      "G": encode_base = 2'd2;
      "T": encode_base = 2'd3;
      default: encode_base = 2'd0;
    endcase
  endfunction

  function automatic [31:0] pack_dna(input string s);
    int i;
    begin
      pack_dna = 32'd0;
      for (i = 0; i < s.len(); i++) begin
        pack_dna |= (32'(encode_base(s[i])) << (2 * i));
      end
    end
  endfunction

  function automatic [31:0] pack_lens(input int query_len, input int ref_len);
    begin
      pack_lens = ((ref_len & 32'h1F) << 5) | (query_len & 32'h1F);
    end
  endfunction

  task automatic wb_write(input [7:0] addr, input [31:0] data);
    begin
      @(posedge wb_clk_i);
      wb_adr_i <= addr;
      wb_dat_i <= data;
      wb_we_i  <= 1'b1;
      wb_stb_i <= 1'b1;
      wb_cyc_i <= 1'b1;
      wb_sel_i <= 4'hF;

      wait (wb_ack_o == 1'b1);

      @(posedge wb_clk_i);
      wb_stb_i <= 1'b0;
      wb_cyc_i <= 1'b0;
      wb_we_i  <= 1'b0;
      wb_adr_i <= 8'd0;
      wb_dat_i <= 32'd0;
    end
  endtask

  task automatic wb_read(input [7:0] addr, output [31:0] data);
    begin
      @(posedge wb_clk_i);
      wb_adr_i <= addr;
      wb_we_i  <= 1'b0;
      wb_stb_i <= 1'b1;
      wb_cyc_i <= 1'b1;
      wb_sel_i <= 4'hF;

      wait (wb_ack_o == 1'b1);
      data = wb_dat_o;

      @(posedge wb_clk_i);
      wb_stb_i <= 1'b0;
      wb_cyc_i <= 1'b0;
      wb_adr_i <= 8'd0;
    end
  endtask

  task automatic wait_done(input [7:0] base);
    int timeout;
    logic [31:0] ctrl;
    begin
      timeout = 10000;
      ctrl = 32'd0;

      while ((ctrl[31] == 1'b0) && timeout > 0) begin
        wb_read(base + REG_CONTROL, ctrl);
        timeout--;
      end

      if (timeout == 0) begin
        $fatal("TIMEOUT waiting for DONE at base %h", base);
      end
    end
  endtask

  task automatic setup_accel(
      input [7:0] base,
      input [31:0] packed_query,
      input [31:0] packed_ref,
      input int query_len,
      input int ref_len
  );
    begin
      wb_write(base + REG_A, packed_query);
      wb_write(base + REG_B, packed_ref);
      wb_write(base + REG_C, pack_lens(query_len, ref_len));
      wb_write(base + REG_D, 32'd1);
    end
  endtask

  initial begin
    logic [31:0] packed_query;
    logic [31:0] packed_ref0;
    logic [31:0] packed_ref1;
    logic [31:0] result0;
    logic [31:0] result1;

    wb_rst_i = 1'b1;
    wb_stb_i = 1'b0;
    wb_cti_i = 3'b000;
    wb_bte_i = 2'b00;
    wb_cyc_i = 1'b0;
    wb_sel_i = 4'hF;
    wb_we_i  = 1'b0;
    wb_adr_i = 8'd0;
    wb_dat_i = 32'd0;

    repeat (5) @(posedge wb_clk_i);
    wb_rst_i = 1'b0;
    repeat (3) @(posedge wb_clk_i);

    packed_query = pack_dna("ACGT");
    packed_ref0  = pack_dna("ACGT"); // expected 8
    packed_ref1  = pack_dna("TTTT"); // expected 2, because query has one T match

    setup_accel(ACC0_BASE, packed_query, packed_ref0, 4, 4);
    setup_accel(ACC1_BASE, packed_query, packed_ref1, 4, 4);

    wb_write(ACC0_BASE + REG_CONTROL, 32'd1);
    wb_write(ACC1_BASE + REG_CONTROL, 32'd1);

    wait_done(ACC0_BASE);
    wait_done(ACC1_BASE);

    wb_read(ACC0_BASE + REG_RESULT, result0);
    wb_read(ACC1_BASE + REG_RESULT, result1);

    $display("Result0 = %0d, expected 8", $signed(result0));
    $display("Result1 = %0d, expected 2", $signed(result1));

    if ($signed(result0) !== 8)
      $fatal("FAILED: accelerator 0 result is wrong");

    if ($signed(result1) !== 2)
      $fatal("FAILED: accelerator 1 result is wrong");

    wb_write(ACC0_BASE + REG_CONTROL, 32'd0);
    wb_write(ACC1_BASE + REG_CONTROL, 32'd0);

    $display("PASSED: dual accelerator top integration test");
    $finish;
  end

endmodule
