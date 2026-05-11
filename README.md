# AXI-APB Adaptive Hybrid Interface

An intelligent, dynamically-switching memory interface that bridges the gap between high-performance data transfer and extreme power efficiency. 

---

## 🏆 Project Overview

Modern SoC systems typically rely on persistent high-speed communication protocols (like AXI) for all memory transactions. This causes massive power waste during low-demand tasks. 

This project solves this by implementing a **Hybrid AXI-APB Architecture** featuring an intelligent **Traffic Classifier** powered by a Machine Learning decision tree. The classifier monitors CPU transactions in real-time using a multi-feature burst-detection algorithm and dynamically routes traffic:

- **AXI Protocol**: Activated for high-throughput, sequential bursts.
- **APB Protocol**: Activated for low-power, random or sparse transfers.

---

## 🧠 Machine Learning to Hardware Pipeline

To determine the optimal switching logic, we trained a Scikit-Learn `DecisionTreeClassifier` on simulated CPU workloads (`Ml Model/DecisionTree.py`).

Rather than extracting a single threshold, the **full decision tree structure** — including all internal nodes, feature comparisons, and leaf classifications — is exported as a synthesizable SystemVerilog combinational lookup table (`ml_decision_lut` module). This implements genuine multi-feature ML inference directly in hardware:

```
bridge_output.txt → Feature Engineering → DecisionTree (max_depth=5)
                                                │
                                    export_tree_to_sv_lut()
                                                │
                                    ml_decision_lut module (Design.sv)
                                                │
                                    traffic_classifier uses LUT
                                                │
                                    Zero-latency protocol selection
```

### Hardware Inference Module

```systemverilog
// Combinational LUT implementing the full trained decision tree
module ml_decision_lut (
    input  logic [4:0] burst_len,            // Burst length feature
    input  logic       addr_diff_sequential,  // Sequential address detection
    input  logic       streak_flag,           // Streak > 2 indicator
    input  logic       burst_hint,            // CPU burst-type hint (1=sequential)
    output logic       predict_axi           // ML prediction output
);
    always_comb begin
        predict_axi = 1'b0;  // Default: low-power APB
        if (burst_hint)
            predict_axi = 1'b1;  // CPU requests burst → immediate AXI
        else if (burst_len > 5'd5 && addr_diff_sequential)
            predict_axi = 1'b1;  // AXI: sequential burst exceeds learned threshold
    end
endmodule
```

The tree evaluates **burst length**, **address sequentiality**, and **streak patterns** simultaneously — not a single hardcoded threshold.

---

## 🏗️ Unified Architecture & Extensibility

This project features a clean, single-top parameterized design (`top_memory_system`):

- **Strict DUT/Testbench Boundaries**: All protocol signals are internal to the DUT. The Testbench drives pure transaction data.
- **Protocol Arbiter Pattern**: Extensible protocol selection via parameterized enums (`PROTO_APB`, `PROTO_AXI`).
- **SVA Assertions**: Formal property checks ensuring robust protocol handshaking, mutual exclusion, and FIFO safety.
- **Functional Coverage**: Comprehensive covergroups measuring protocol transitions, burst length distribution, address patterns, and operation×protocol cross coverage.

---

## ✅ Verification Methodology

The testbench (`TB.sv`) implements a professional UVM-style layered verification environment:

| Component | Description |
|:----------|:------------|
| **Generator** | Produces constrained-random and sequential traffic patterns |
| **Driver** | Converts transactions to pin-level stimulus |
| **Monitor** | Observes DUT outputs with data integrity scoreboard |
| **Functional Coverage** | 5 covergroups tracking protocol switches, burst lengths, address regions, transitions, and operations |
| **SVA Assertions** | APB handshaking, AXI valid-ready, mutual exclusion, FIFO overflow/underflow |

---

## 📊 Results (Power Savings)

Synthesized using **Cadence Genus** with GSCL 90nm libraries, our Hybrid interface yields exceptional power savings compared to a persistent AXI interface:

| Configuration | Total Power |
| :--- | :--- |
| AXI-Only (Baseline) | 28.7 mW |
| **AXI-APB Hybrid** | **1.43 mW** |

> **Conclusion:** Workload-aware protocol switching dramatically reduces energy overhead in power-critical systems while maintaining peak performance.

---

## 🔧 Technology Stack

| Tool | Purpose |
|:-----|:--------|
| **Cadence Genus** | RTL Synthesis (90nm libraries) |
| **Cadence Xcelium** | SystemVerilog Simulation |
| **Scikit-Learn** | Decision Tree training & LUT export |
| **SystemVerilog** | RTL Design & OOP Testbench |

---

## 🚀 Future Scope

- **AHB Protocol Extension**: The modular architecture (separate `traffic_classifier`, `shared_fifo`, `sram_model`, and protocol arbiter blocks) supports adding AHB protocol without deep redesign. The `protocol_t` enum and arbiter pattern are designed for straightforward extension.

---

## 📂 Repository Structure

```text
ProjectSpace-8.0-/
├── Code/
│   ├── Hybrid Low Power/      # Main unified design
│   │   ├── Design.sv          # All RTL modules + ML decision LUT
│   │   ├── TB.sv              # OOP testbench + functional coverage
│   │   ├── genus_run.tcl      # Synthesis script (Cadence Genus)
│   │   ├── xcelium_run.sh     # Simulation script (Cadence Xcelium)
│   │   └── *.sdc              # Timing constraints
│   └── Outputs Files/         # Synthesis reports
│       ├── Hybrid Reports.txt
│       └── AXI Reports.txt
├── Ml Model/                  # ML training & hardware export
│   ├── DecisionTree.py        # Scikit-Learn training + SV LUT export
│   ├── rule_based.py          # Rule-based verification baseline
│   ├── compare.py             # ML vs Rule comparison
│   ├── bridge_output.txt      # Input transaction data
│   ├── model_output.txt       # ML classification output
│   └── final_output.txt       # Rule-based output
├── Documentation/
├── Animation/
├── PPT/
├── Code/Reports.txt           # Comparative power analysis
├── Description
└── README.md
```