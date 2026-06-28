# VLSI_Hackathon

# 🚀 Smith-Waterman Hardware Accelerator on RISC-V

A hardware/software co-design project developed during a RISC-V Hackathon to accelerate the **Smith-Waterman DNA sequence alignment algorithm**.

## 🧬 The Challenge

Smith-Waterman is a Dynamic Programming algorithm used for local DNA sequence alignment. While highly accurate, it performs **millions of repetitive computations** and memory accesses, making it computationally expensive.

Our goal was simple:

> **Make Smith-Waterman significantly faster by combining software optimizations with a custom FPGA hardware accelerator.**

---

## 💡 Our Approach

Instead of jumping straight into hardware, we followed a **measure → optimize → accelerate** workflow.

### ⚡ Software Optimizations
- 🔄 **Rolling Rows** – reduced DP memory from full matrices to rolling buffers.
- 🔁 **Pointer Swapping** – eliminated unnecessary row copying.
- 🧬 **2-bit DNA Packing** – packed 16 DNA bases into a single 32-bit word, reducing memory footprint and communication overhead.

### 🖥️ Hardware Acceleration
After profiling the algorithm, we identified the real bottleneck and moved the **entire Dynamic Programming row computation** into a custom FPGA accelerator connected to the RISC-V processor through a **Wishbone Bus**.

The accelerator:
- Initializes DP buffers
- Computes one complete DP row per invocation
- Updates the best alignment score internally
- Returns the final score to the CPU

---

## 📈 Results

| Implementation | Clock Cycles |
|---------------|-------------:|
| Original Software | 1,157,276 |
| Final Hardware-Accelerated Version | **32,350** |

🎉 **35.8× Speedup**

📉 **97.2% reduction in execution time**

---

## 🛠️ Technologies

- RISC-V Processor
- Nexys A7 FPGA
- SystemVerilog
- C
- Vivado
- Wishbone Bus
- PSP Performance Counters

---

## 📚 Project Highlights

- Hardware/Software Co-Design
- Dynamic Programming Acceleration
- FPGA Development
- Performance Profiling
- Memory Optimization
- Computer Architecture

---

*"Measure first. Optimize second. Accelerate last."* 🚀
