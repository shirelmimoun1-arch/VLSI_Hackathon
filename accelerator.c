/* -------------------------------------------------- */
/* Software driver for two Smith-Waterman accelerators */
/* -------------------------------------------------- */

#include <psp_api.h>

/* Each accelerator gets a separate 32-byte MMIO region. */
#define ACC0_BASE 0x80001300
#define ACC1_BASE 0x80001320

#define ACCELERATOR_REG_CONTROL  0x00
#define ACCELERATOR_REG_A        0x04
#define ACCELERATOR_REG_B        0x08
#define ACCELERATOR_REG_C        0x0C
#define ACCELERATOR_REG_D        0x10
#define ACCELERATOR_REG_RESULT   0x14

#define REG(base, off) ((base) + (off))

/* Direct memory-mapped register access macros. */
#define READ_GPIO(dir) (*(volatile unsigned *)(dir))
#define WRITE_GPIO(dir, value) (*(volatile unsigned *)(dir) = (value))

/*
 * REG_C layout:
 * bits [4:0] = query length
 * bits [9:5] = reference length
 */
#define PACK_LENS(q_len, r_len) \
    ((((r_len) & 0x1F) << 5) | ((q_len) & 0x1F))

/* REG_D[0] = 1 means compute one full Smith-Waterman alignment. */
#define CMD_COMPUTE_FULL 1u

/*
 * Write one query/reference pair into a selected accelerator.
 * This only configures the accelerator; it does not start it yet.
 */
static inline void hw_setup_alignment(
    unsigned base,
    unsigned packed_query,
    unsigned packed_ref,
    int query_len,
    int ref_len)
{
  WRITE_GPIO(REG(base, ACCELERATOR_REG_A), packed_query);
  WRITE_GPIO(REG(base, ACCELERATOR_REG_B), packed_ref);
  WRITE_GPIO(REG(base, ACCELERATOR_REG_C), PACK_LENS(query_len, ref_len));
  WRITE_GPIO(REG(base, ACCELERATOR_REG_D), CMD_COMPUTE_FULL);
}

/* Start one accelerator by setting GO in its control register. */
static inline void hw_start(unsigned base)
{
  WRITE_GPIO(REG(base, ACCELERATOR_REG_CONTROL), 1);
}

/* Wait until one accelerator asserts DONE in CONTROL[31]. */
static inline void hw_wait_done(unsigned base)
{
  while ((READ_GPIO(REG(base, ACCELERATOR_REG_CONTROL)) & 0x80000000) == 0) {
    /* busy wait */
  }
}

/* Clear GO after DONE was observed, allowing the accelerator to return to IDLE. */
static inline void hw_clear_go(unsigned base)
{
  WRITE_GPIO(REG(base, ACCELERATOR_REG_CONTROL), 0);
}

/* Read the final best alignment score from one accelerator. */
static inline int hw_read_result(unsigned base)
{
  return (int)READ_GPIO(REG(base, ACCELERATOR_REG_RESULT));
}

/*
 * Single-accelerator wrapper.
 * Kept for compatibility and for testing one accelerator alone.
 */
int hw_compute_alignment(
    unsigned packed_query,
    unsigned packed_ref,
    int query_len,
    int ref_len)
{
  hw_setup_alignment(ACC0_BASE, packed_query, packed_ref, query_len, ref_len);

  hw_start(ACC0_BASE);
  hw_wait_done(ACC0_BASE);

  int score = hw_read_result(ACC0_BASE);

  hw_clear_go(ACC0_BASE);

  return score;
}

/*
 * Compute two independent Smith-Waterman alignments in parallel.
 * Both accelerators receive the same query but different references.
 */
void hw_compute_two_alignments(
    unsigned packed_query,
    unsigned packed_ref0,
    unsigned packed_ref1,
    int query_len,
    int ref_len0,
    int ref_len1,
    int *score0,
    int *score1)
{
  hw_setup_alignment(ACC0_BASE, packed_query, packed_ref0, query_len, ref_len0);
  hw_setup_alignment(ACC1_BASE, packed_query, packed_ref1, query_len, ref_len1);

  /* Start both accelerators before waiting, so they run in parallel. */
  hw_start(ACC0_BASE);
  hw_start(ACC1_BASE);

  hw_wait_done(ACC0_BASE);
  hw_wait_done(ACC1_BASE);

  *score0 = hw_read_result(ACC0_BASE);
  *score1 = hw_read_result(ACC1_BASE);

  hw_clear_go(ACC0_BASE);
  hw_clear_go(ACC1_BASE);
}
