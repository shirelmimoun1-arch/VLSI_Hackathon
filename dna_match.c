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

extern void hw_compute_two_alignments(
    unsigned packed_query,
    unsigned packed_ref0,
    unsigned packed_ref1,
    int query_len,
    int ref_len0,
    int ref_len1,
    int *score0,
    int *score1
);

/*
 * Encode one DNA base into its 2-bit representation:
 * A=00, C=01, G=10, T=11.
 */
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

/*
 * Pack a DNA sequence into a single 32-bit word.
 * Each base occupies 2 bits, allowing sequences of up to 16 bases.
 */
static inline unsigned pack_dna(const char *s)
{
  unsigned packed = 0;

  for (int i = 0; i < MAX_DNA_LEN && s[i] != '\0'; i++) {
    packed |= encode_base(s[i]) << (2 * i);
  }

  return packed;
}

/*
 * Pack the query and reference sequences, execute two hardware
 * accelerators in parallel, and report execution cycles and scores.
 */
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

  /* Pack the query once since it is reused for all references. */
  unsigned packed_query = pack_dna(query);

  int ref_len[NUM_OF_REFS];
  unsigned packed_ref[NUM_OF_REFS];

  /*
   * Pre-pack all reference sequences before timing to measure
   * accelerator performance without software packing overhead.
   */
  for (int i = 0; i < NUM_OF_REFS; i++) {
    ref_len[i] = strlen(references[i]);
    packed_ref[i] = pack_dna(references[i]);
  }

  pspMachinePerfMonitorEnableAll();
  pspMachinePerfCounterSet(D_PSP_COUNTER0, D_CYCLES_CLOCKS_ACTIVE);

  /* Start measuring execution cycles. */
  int cyc_beg = pspMachinePerfCounterGet(D_PSP_COUNTER0);

  /*
   * Process references in pairs.
   * Each pair is computed by two accelerators running in parallel.
   */
  for (int i = 0; i < NUM_OF_REFS; i += 2) {
    hw_compute_two_alignments(
        packed_query,
        packed_ref[i],
        packed_ref[i + 1],
        query_len,
        ref_len[i],
        ref_len[i + 1],
        &score[i],
        &score[i + 1]
    );
  }

  /* Stop measuring execution cycles. */
  int cyc_end = pspMachinePerfCounterGet(D_PSP_COUNTER0);

  /* Report total accelerator execution time in CPU cycles. */
  printf("Total Workload Cycles = %d\n", cyc_end - cyc_beg);

  /* Display the alignment score obtained for each reference sequence. */
  printf("\n--- Verification Scores ---\n");

  for (int i = 0; i < NUM_OF_REFS; i++) {
    printf("Reference %d score = %d\n", i, score[i]);
  }

  return 0;
}
