#include <psp_api.h>

/* -------------------------------------------------- */
/* Accelerator MMIO registers                         */
/* -------------------------------------------------- */

#define ACCELERATOR_REG_CONTROL  0x80001300
#define ACCELERATOR_REG_A        0x80001304
#define ACCELERATOR_REG_B        0x80001308
#define ACCELERATOR_REG_C        0x8000130C
#define ACCELERATOR_REG_D        0x80001310
#define ACCELERATOR_REG_RESULT   0x80001314

#define READ_GPIO(dir) (*(volatile unsigned *)(dir))
#define WRITE_GPIO(dir, value) (*(volatile unsigned *)(dir) = (value))

/*
 * REG_C layout:
 * bits [4:0] = query length
 * bits [9:5] = reference length
 */
#define PACK_LENS(q_len, r_len) \
    ((((r_len) & 0x1F) << 5) | ((q_len) & 0x1F))

/* -------------------------------------------------- */
/* Start accelerator and wait until DONE              */
/* -------------------------------------------------- */

static inline void accel_start_and_wait(void)
{
    // Raise GO 
    WRITE_GPIO(ACCELERATOR_REG_CONTROL, 1);

    // Wait for DONE = CONTROL[31]
    while ((READ_GPIO(ACCELERATOR_REG_CONTROL) & 0x80000000) == 0) {
        // wait 
    }

    // Lower GO 
    WRITE_GPIO(ACCELERATOR_REG_CONTROL, 0);
} 

/* -------------------------------------------------- */
/* Initialize accelerator for one query/reference pair */
/* -------------------------------------------------- */

static void hw_row_init(
        unsigned packed_query,
        unsigned packed_ref,
        int query_len,
        int ref_len)
{
    WRITE_GPIO(ACCELERATOR_REG_A, packed_query);
    WRITE_GPIO(ACCELERATOR_REG_B, packed_ref);
    WRITE_GPIO(ACCELERATOR_REG_C, PACK_LENS(query_len, ref_len));

    /*
     * REG_D = 1 means INIT command.
     * Accelerator stores inputs and initializes internal rolling rows.
     */
    WRITE_GPIO(ACCELERATOR_REG_D, 1);
    accel_start_and_wait();
}

/* -------------------------------------------------- */
/* Compute one DP row                                 */
/* -------------------------------------------------- */


static int hw_compute_next_row(void)
{
    //REG_D = 0 means COMPUTE_NEXT_ROW command.
    
    WRITE_GPIO(ACCELERATOR_REG_D, 0);

    accel_start_and_wait();
}

/* -------------------------------------------------- */
/* Public function used by dna_match.c                */
/* -------------------------------------------------- */

int hw_compute_all_rows(
        unsigned packed_query,
        unsigned packed_ref,
        int query_len,
        int ref_len)
{

    hw_row_init(
        packed_query,
        packed_ref,
        query_len,
        ref_len
    );

    for (int row = 0; row < query_len; row++) {
        hw_compute_next_row();
    }
    // hw_compute_next_row()return the best score in each iteration
    // but we are interested in the final best score that is stores in the 
    // result register
    return (int)READ_GPIO(ACCELERATOR_REG_RESULT);
}

