#if defined(D_NEXYS_A7)
   #include <bsp_printf.h>
   #include <bsp_mem_map.h>
   #include <bsp_version.h>
#else
   PRE_COMPILED_MSG("no platform was defined")
#endif

#include <psp_api.h>
#include <stdio.h>
#include <string.h>

#define MAX_DNA_LEN 16
#define NUM_OF_REFS 8

extern int hw_compute_all_rows(
        unsigned packed_query,
        unsigned packed_ref,
        int query_len,
        int ref_len);


/* A = 00, C = 01, G = 10, T = 11 */
static inline unsigned encode_base(char c)
{
    switch (c) {
        case 'A': return 0;
        case 'C': return 1;
        case 'G': return 2;
        case 'T': return 3;
        default:  return 0;
    }
}

static inline unsigned pack_dna(const char *s)
{
    unsigned packed = 0;

    for (int i = 0; i < MAX_DNA_LEN && s[i] != '\0'; i++) {
        packed |= encode_base(s[i]) << (2 * i);
    }

    return packed;
}

int main(void)
{
    const char *query = "ACGTCGTACGTACGTA";

    const char *references[NUM_OF_REFS] = {
        "ACGTACGTACGTACGT",
        "ACGTTCGTACGTACGT",
        "ACGTACGGACGTACGT",
        "TTTTTTTTTTTTTTTT",
        "ACGTACGTTCGTACGT",
        "ACGTACGTACGTACGA",
        "ACGTTTGTACGTACGT",
        "ACGTACGTGCGTACGT"
    };

    int score[NUM_OF_REFS];

    int query_len = strlen(query);
    unsigned packed_query = pack_dna(query);

    int cyc_beg, cyc_end;

    pspMachinePerfMonitorEnableAll();
    pspMachinePerfCounterSet(D_PSP_COUNTER0, D_CYCLES_CLOCKS_ACTIVE);

    int total_go_done_all = 0;
    int total_call_all = 0;

    cyc_beg = pspMachinePerfCounterGet(D_PSP_COUNTER0);

    for (int i = 0; i < NUM_OF_REFS; i++) {
        int ref_len = strlen(references[i]);
        unsigned packed_ref = pack_dna(references[i]);

        score[i] = hw_compute_all_rows(
            packed_query,
            packed_ref,
            query_len,
            ref_len
        );
    }

    cyc_end = pspMachinePerfCounterGet(D_PSP_COUNTER0);

    int total_workload = cyc_end - cyc_beg;
    int overhead = total_call_all - total_go_done_all;

    printf("Total Workload Cycles = %d\n", cyc_end - cyc_beg);

    printf("\n--- Verification Scores ---\n");

    for (int i = 0; i < NUM_OF_REFS; i++) {
        printf("Reference %d score = %d\n", i, score[i]);
    }

    return 0;
}