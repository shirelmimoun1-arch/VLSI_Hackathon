# 🚀 Smith-Waterman Hardware Accelerator on RISC-V

A hardware/software co-design project developed during a RISC-V Hackathon to accelerate the **Smith-Waterman DNA sequence alignment algorithm** using software optimization and custom FPGA hardware.

## 🧬 The Challenge

Smith-Waterman is a dynamic programming algorithm used for local DNA sequence alignment. Its computation requires repeatedly evaluating alignment states across many DP cells, resulting in significant computation and memory activity when processing multiple reference sequences.

Our goal was:

> **Accelerate Smith-Waterman by optimizing the software representation and offloading the computationally intensive alignment process to dedicated FPGA hardware.**

---

## 💡 Our Approach

We followed a **measure → optimize → accelerate** workflow, starting with a software implementation and progressively moving computation into dedicated hardware.

### ⚡ Software Optimizations

- 🔄 **Rolling Rows** – reduced DP storage by keeping only the rows required for the current computation instead of full DP matrices.
- 🔁 **Pointer Swapping** – reduced unnecessary row copying in the optimized software implementation.
- 🧬 **2-bit DNA Packing** – encoded each DNA base using 2 bits, allowing sequences of up to 16 bases to fit in a single 32-bit word.
- 📦 **Pre-Packed References** – packed reference sequences before performance measurement so the final benchmark focuses on accelerator execution and communication overhead.

### 🖥️ FPGA Hardware Acceleration

The final architecture contains **two independent Smith-Waterman accelerator cores** connected to the RISC-V processor through a **Wishbone memory-mapped interface**.

Each accelerator receives:

- A packed query sequence
- A packed reference sequence
- Query and reference lengths
- A command to start a full alignment

A single `GO` command launches the complete Smith-Waterman alignment in hardware.

The accelerator's internal finite-state machine performs initialization, DP-cell computation, row transitions, best-score tracking, and completion without requiring CPU intervention for each row.

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
```

The software processes the eight reference sequences in **four pairs**, starting both accelerators before waiting for their results so their computations overlap.

---

## 🧠 Accelerator Architecture

Each Smith-Waterman accelerator implements the alignment algorithm as a hardware finite-state machine:

```text
IDLE
  ↓
INIT
  ↓
ROW_START
  ↓
CELL ──→ CELL ──→ ...
  ↓
COPY_ROW
  │
  ├── More query rows ──→ ROW_START
  │
  └── Alignment complete ──→ FINISH
                                ↓
                               DONE
```

### Rolling DP Storage

Instead of storing complete DP matrices, each accelerator maintains only the state required for the current and previous rows:

- `M_prev` / `M_curr` – alignment scores
- `I_prev` / `I_curr` – insertion-gap states
- `D_curr` – deletion-gap state

This reduces hardware storage requirements while preserving the dependencies required by the Smith-Waterman recurrence.

### Early Termination

The accelerator computes the maximum theoretically possible alignment score:

```text
max_score = min(query_length, reference_length) × MATCH
```

If this score is reached during computation, the accelerator terminates early because no higher Smith-Waterman score is possible.

### Dual-Accelerator Parallelism

The top-level hardware design instantiates **two independent accelerator cores**, each with its own register bank.

```text
Accelerator 0 MMIO: 0x80001300 – 0x8000131F
Accelerator 1 MMIO: 0x80001320 – 0x8000133F
```

The CPU configures both accelerators and starts them before polling for completion, allowing two alignments to execute concurrently.

---

## 🔄 Hardware/Software Interaction

For each pair of reference sequences, the software performs:

```text
Configure Accelerator 0
Configure Accelerator 1
        ↓
Start Accelerator 0
Start Accelerator 1
        ↓
   Parallel Execution
        ↓
Wait for DONE
        ↓
Read both alignment scores
```

The CPU communicates with the accelerators using memory-mapped registers for:

- Packed query sequence
- Packed reference sequence
- Sequence lengths
- Control (`GO` / `DONE`)
- Final alignment score

---

## 📈 Results

| Implementation | Clock Cycles |
|---|---:|
| Original Software | 1,157,276 |
| Final Hardware-Accelerated Version | **4,390** |

### 🚀 ~263.6× fewer cycles

### 📉 ~99.62% reduction in clock cycles

The final measured workload processes **eight reference sequences** using the dual-accelerator architecture.

---

## 🔬 Hardware Validation

The final implementation was deployed and tested on a **Nexys A7 FPGA**.

The measured workload completed in **4,390 clock cycles** while producing the expected Smith-Waterman alignment scores.

![Smith-Waterman Accelerator running on Nexys A7](images/nexys-a7-results.jpeg)

*Final hardware-accelerated implementation running on the Nexys A7 FPGA, showing the measured 4,390-cycle workload and verification scores.*

---

## 🧪 Verification

The design was verified at multiple levels:

- **Accelerator core logic** – Smith-Waterman score computation
- **Wishbone register interface** – configuration, control, and result access
- **Top-level integration** – two independent accelerator instances
- **Parallel operation** – both accelerators are started before software waits for completion
- **FPGA validation** – final scores and cycle count verified on the Nexys A7 board

The top-level SystemVerilog testbench configures both accelerators through the Wishbone interface, launches two independent alignments, waits for their `DONE` signals, and checks the returned scores against expected values.

---

## 🛠️ Technologies

- **RISC-V Processor**
- **Nexys A7 FPGA**
- **SystemVerilog**
- **C**
- **Xilinx Vivado**
- **Wishbone Bus**
- **Memory-Mapped I/O (MMIO)**
- **PSP Performance Counters**

---

## 📚 Project Highlights

- Hardware/Software Co-Design
- FPGA-Based Algorithm Acceleration
- Dual Hardware Accelerator Architecture
- Parallel Alignment Processing
- SystemVerilog RTL Development
- Finite-State Machine Design
- RISC-V / Wishbone Integration
- Memory-Mapped Hardware Control
- Dynamic Programming Acceleration
- Rolling-Row DP Storage
- 2-bit DNA Encoding
- Early-Termination Optimization
- Performance Profiling and Benchmarking
- FPGA Hardware Validation

---

## 🏆 Performance Improvement

The project demonstrates how progressively moving computation from software into specialized hardware can significantly reduce the number of cycles required for a computational workload.

The final architecture combines:

1. Compact **2-bit DNA representation**
2. Memory-efficient **rolling DP state**
3. A hardware FSM that performs a **complete alignment per command**
4. **Early termination** when the theoretical maximum score is reached
5. **Two parallel Smith-Waterman accelerator cores**
6. Pairwise processing of multiple reference sequences
7. Memory-mapped integration with a **RISC-V processor through Wishbone**

Starting from an original software implementation requiring **1,157,276 clock cycles**, the final FPGA-accelerated workload completed in **4,390 clock cycles**:

- **~263.6× fewer cycles**
- **~99.62% reduction in clock cycles**

---

*"Measure first. Optimize second. Accelerate last."* 🚀
