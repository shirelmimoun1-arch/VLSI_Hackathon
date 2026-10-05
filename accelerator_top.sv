//////////////////////////////////////////////////////////////////////
////  accelerator_top.sv                                          ////
////  Two parallel Smith-Waterman accelerators                    ////
//////////////////////////////////////////////////////////////////////

module accelerator_top (
    input  logic        wb_clk_i,

    // WISHBONE interface
    input  logic        wb_rst_i,
    input  logic        wb_stb_i,
    input  logic [2:0]  wb_cti_i,
    input  logic [1:0]  wb_bte_i,
    input  logic        wb_cyc_i,
    input  logic [3:0]  wb_sel_i,
    input  logic        wb_we_i,
    input  logic [7:0]  wb_adr_i,
    input  logic [31:0] wb_dat_i,
    output logic [31:0] wb_dat_o,

    output logic        wb_ack_o,
    output logic        wb_err_o,
    output logic        wb_rty_o,
    output logic        int_o
);

parameter SIM   = 0;
parameter debug = 0;

/* Wishbone internal signals */
logic [31:0] wb_data_reg_out;
logic [31:0] wb_data_reg_in;
logic [7:0]  wb_adr_int;
logic        we_o;
logic        re_o;

/* Accelerator 0 register signals */
logic [31:0] reg_a0, reg_b0, reg_c0, reg_d0, reg_result0;
logic        go0, done0;

/* Accelerator 1 register signals */
logic [31:0] reg_a1, reg_b1, reg_c1, reg_d1, reg_result1;
logic        go1, done1;

/*
 * Address map:
 * accelerator 0: 0x00 - 0x1F
 * accelerator 1: 0x20 - 0x3F
 */
logic sel0, sel1;
logic [7:0] wb_adr_acc0;
logic [7:0] wb_adr_acc1;

logic [31:0] wb_data_reg_in0;
logic [31:0] wb_data_reg_in1;

assign sel0 = (wb_adr_int < 8'h20);
assign sel1 = (wb_adr_int >= 8'h20 && wb_adr_int < 8'h40);

assign wb_adr_acc0 = wb_adr_int;
assign wb_adr_acc1 = wb_adr_int - 8'h20;

/* No interrupt is used */
assign int_o = 1'b0;

/* Select read data from the addressed accelerator register bank */
always_comb begin
    if (sel0)
        wb_data_reg_in = wb_data_reg_in0;
    else if (sel1)
        wb_data_reg_in = wb_data_reg_in1;
    else
        wb_data_reg_in = 32'b0;
end

/* Wishbone interface */
accelerator_wb wb_interface (
    .clk             (wb_clk_i),
    .wb_rst_i        (wb_rst_i),

    .wb_we_i         (wb_we_i),
    .wb_stb_i        (wb_stb_i),
    .wb_cti_i        (wb_cti_i),
    .wb_bte_i        (wb_bte_i),
    .wb_cyc_i        (wb_cyc_i),
    .wb_ack_o        (wb_ack_o),
    .wb_sel_i        (wb_sel_i),
    .wb_adr_i        (wb_adr_i),
    .wb_dat_i        (wb_dat_i),
    .wb_dat_o        (wb_dat_o),
    .wb_err_o        (wb_err_o),
    .wb_rty_o        (wb_rty_o),

    .wb_adr_reg      (wb_adr_int),
    .wb_data_reg_in  (wb_data_reg_in),
    .wb_data_reg_out (wb_data_reg_out),
    .we_o            (we_o),
    .re_o            (re_o)
);

/* Register bank for accelerator 0 */
accelerator_regs regs0 (
    .clk        (wb_clk_i),
    .wb_rst_i   (wb_rst_i),

    .wb_addr_i  (wb_adr_acc0),
    .wb_dat_i   (wb_data_reg_out),
    .wb_dat_o   (wb_data_reg_in0),
    .wb_we_i    (we_o && sel0),
    .wb_re_i    (re_o && sel0),

    .reg_a      (reg_a0),
    .reg_b      (reg_b0),
    .reg_c      (reg_c0),
    .reg_d      (reg_d0),
    .go         (go0),
    .done       (done0),
    .reg_result (reg_result0)
);

/* Register bank for accelerator 1 */
accelerator_regs regs1 (
    .clk        (wb_clk_i),
    .wb_rst_i   (wb_rst_i),

    .wb_addr_i  (wb_adr_acc1),
    .wb_dat_i   (wb_data_reg_out),
    .wb_dat_o   (wb_data_reg_in1),
    .wb_we_i    (we_o && sel1),
    .wb_re_i    (re_o && sel1),

    .reg_a      (reg_a1),
    .reg_b      (reg_b1),
    .reg_c      (reg_c1),
    .reg_d      (reg_d1),
    .go         (go1),
    .done       (done1),
    .reg_result (reg_result1)
);

/* Accelerator core 0 */
accelerator accelerator0 (
    .clk        (wb_clk_i),
    .wb_rst_i   (wb_rst_i),

    .reg_a      (reg_a0),
    .reg_b      (reg_b0),
    .reg_c      (reg_c0),
    .reg_d      (reg_d0),

    .go         (go0),
    .done       (done0),
    .reg_result (reg_result0)
);

/* Accelerator core 1 */
accelerator accelerator1 (
    .clk        (wb_clk_i),
    .wb_rst_i   (wb_rst_i),

    .reg_a      (reg_a1),
    .reg_b      (reg_b1),
    .reg_c      (reg_c1),
    .reg_d      (reg_d1),

    .go         (go1),
    .done       (done1),
    .reg_result (reg_result1)
);

endmodule
