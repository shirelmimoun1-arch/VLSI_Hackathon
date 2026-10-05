# 🚀 Smith-Waterman Hardware Accelerator on RISC-V

A hardware/software co-design project developed during a RISC-V Hackathon to accelerate the **Smith-Waterman DNA sequence alignment algorithm** using software optimization and custom FPGA hardware.

## 🧬 The Challenge

Smith-Waterman is a Dynamic Programming algorithm used for local DNA sequence alignment. Its DP computation requires repeatedly evaluating alignment states across many cells, resulting in significant computation and memory activity when processing multiple reference sequences.

Our goal was:

> **Accelerate Smith-Waterman by optimizing the software representation and offloading the computationally intensive alignment process to dedicated FPGA hardware.**

---

## 💡 Our Approach

We followed a **measure → optimize → accelerate** workflow, starting with a software implementation and progressively moving computation into dedicated hardware.

### ⚡ Software Optimizations

- 🔄 **Rolling Rows** – reduced DP storage by keeping only the rows required for the current computation instead of full DP matrices.
- 🔁 **Pointer Swapping** – reduced unnecessary copying in the optimized software implementation.
- 🧬 **2-bit DNA Packing** – encoded each DNA base using 2 bits, allowing sequences of up to 16 bases to fit in a single 32-bit word.
- 📦 **Pre-Packed References** – reference sequences are packed before performance measurement so the final benchmark focuses on accelerator execution and communication overhead.

### 🖥️ FPGA Hardware Acceleration

The final architecture contains **two independent Smith-Waterman accelerator cores** connected to the RISC-V processor through a **Wishbone memory-mapped interface**.

Each accelerator receives:

- A packed query sequence
- A packed reference sequence
- Query and reference lengths
- A command to start a full alignment

A single `GO` command launches the complete Smith-Waterman alignment in hardware. The accelerator's internal finite-state machine performs initialization, DP-cell computation, row transitions, score tracking, and completion without requiring CPU intervention for each row.

The two accelerator cores occupy separate MMIO regions and can process **two independent reference sequences concurrently**.

```text
                         RISC-V CPU
                             │
                      Wishbone / MMIO
                             │
              ┌──────────────┴──────────────┐
              │                             │
        Accelerator 0                 Accelerator 1
              │                             │
       Reference 2k                  Reference 2k+1
              │                             │
       Full Alignment                Full Alignment
              │                             │
              └──────── Scores ─────────────┘
