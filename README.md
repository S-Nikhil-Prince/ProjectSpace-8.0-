# AXI-APB Adaptive Hybrid Interface

An intelligent, dynamically-switching memory interface that bridges the gap between high-performance data transfer and extreme power efficiency. 

---

## 🏆 Project Overview

Modern SoC systems typically rely on persistent high-speed communication protocols (like AXI) for all memory transactions. This causes massive power waste during low-demand tasks. 

This project solves this by implementing a **Hybrid AXI-APB Architecture** featuring an intelligent **Traffic Classifier** powered by Machine Learning heuristics. The classifier monitors CPU transactions in real-time using a windowed burst-detection algorithm and dynamically routes traffic:

- **AXI Protocol**: Activated for high-throughput, sequential bursts.
- **APB Protocol**: Activated for low-power, random or sparse transfers.

---

## 🧠 Machine Learning to Hardware Pipeline

To determine the optimal switching threshold, we trained a Scikit-Learn Decision Tree model on simulated CPU workloads (`Ml Model/DecisionTree.py`). 

The model successfully learned the optimal burst threshold to justify the energy overhead of protocol switching. This learned logic was then synthesized directly into our SystemVerilog hardware as a zero-latency inference block:

```systemverilog
// Synthesizable ML Inference Rule in Hardware
parameter BURST_THRESHOLD = 5; // Derived from ML model max_depth

if (burst_len >= BURST_THRESHOLD) begin
    // Switch to High-Performance AXI
end else begin
    // Remain in Low-Power APB
end
```

---

## 🏗️ Unified Architecture & Extensibility

Unlike split architectures, this project features a clean, single-top parameterized design (`top_memory_system`):

- **Strict DUT/Testbench Boundaries**: All protocol signals are internal to the DUT. The Testbench drives pure transaction data.
- **Protocol Arbiter Pattern**: Extensible protocol selection via parameterized enums (`PROTO_APB`, `PROTO_AXI`, `PROTO_AHB`).
- **SVA Assertions**: Formal property checks ensuring robust protocol handshaking and mutual exclusion.

---

## 📊 Results (Power Savings)

Synthesized using **Cadence Genus** with 90nm libraries, our Hybrid interface yields exceptional power savings compared to a persistent AXI interface:

| Configuration | Total Power |
| :--- | :--- |
| AXI-Only (Baseline) | 28.7 mW |
| **AXI-APB Hybrid** | **16.23 mW** |

> **Conclusion:** Workload-aware protocol switching dramatically reduces energy overhead in power-critical systems while maintaining peak performance.

---

## 📂 Repository Structure

```text
ProjectSpace-8.0-/
├── Code/
│   ├── Hybrid Low Power/      # Main unified design
│   │   ├── Design.sv          # All RTL modules
│   │   ├── TB.sv              # OOP testbench
│   │   ├── genus_run.tcl      # Synthesis script
│   │   ├── xcelium_run.sh     # Simulation script
│   │   └── constraints.sdc    # Timing constraints
│   └── Outputs Files/         # Synthesis reports
│       ├── Hybrid Reports.txt
│       └── AXI Reports.txt
├── Ml Model/                  # ML training & validation
│   ├── DecisionTree.py        # Scikit-Learn Decision Tree
│   ├── rule_based.py          # Rule-based verification
│   ├── compare.py             # ML vs Rule comparison
│   ├── bridge_output.txt      # Input transaction data
│   ├── model_output.txt       # ML classification output
│   └── final_output.txt       # Rule-based output
├── Documentation/
├── Animation/
├── PPT/
├── Code/Reports.txt           # Comparative analysis
├── Description
└── README.md                  # Professional project documentation
```