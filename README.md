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
                                    ml_decision_lut.sv (auto-generated)
                                                │
                            ┌───────────────────┤
                            │                   │
                    Auto-copied to          Verified against
                    Code/Hybrid Low Power/  rule_based.py baseline
                            │
                    traffic_classifier uses LUT
                            │
                    Zero-latency protocol selection
```

### Automated Synchronization

The ML model and hardware LUT are **automatically synchronized** via the build pipeline:

```bash
# Single command trains model, exports LUT, and copies to design directory
python DecisionTree.py
# Or via Makefile:
make ml
```

The `DecisionTree.py` script:
1. Trains the model on `bridge_output.txt`
2. Exports the tree as `ml_decision_lut.sv`
3. **Auto-copies** the generated LUT to `Code/Hybrid Low Power/`
4. **Auto-verifies** against the rule-based baseline (`final_output.txt`)

This eliminates any risk of model-hardware divergence.

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

---

## 🏗️ Architecture & Extensibility

### Modular Design

The project features a clean, parameterized architecture with **5 standalone modules**:

| Module | Role |
|:-------|:-----|
| `traffic_classifier` | ML-driven burst detection with sliding window |
| `ml_decision_lut` | Combinational decision tree inference engine |
| `protocol_arbiter` | **Parameterized** multi-protocol signal generation |
| `shared_fifo` | Parameterized FIFO with 3-case count logic |
| `sram_model` | Synchronous registered-read SRAM model |

### Parameterized Protocol Arbiter

The protocol arbiter is extracted as a **standalone, parameterized module** supporting incremental protocol extension:

```systemverilog
module protocol_arbiter #(
    parameter ENABLE_AHB = 0   // Set to 1 to activate AHB protocol path
)( ... );
```

Key properties:
- **Clock-gating enables** (`axi_clk_en`, `apb_clk_en`, `ahb_clk_en`) per protocol for power optimization
- **AHB stub** conditionally compiled via `generate` block — activation requires only a parameter change
- **Mutual exclusion** enforced at the signal level, verified by SVA assertions

### AHB Extension Path

Adding AHB requires **only** changing `ENABLE_AHB=1` at instantiation. The `protocol_t` enum already includes `PROTO_AHB = 2'b10`, and the generate block contains the AHB-Lite signal scaffolding (hsel, htrans, hwrite, hready, hresp).

### Design Principles
- **Strict DUT/Testbench Boundaries**: All protocol signals are internal to the DUT. The Testbench drives pure transaction data.
- **8 SVA Assertions**: APB handshaking (2), AXI write+read channel handshakes (3), protocol mutual exclusion (1), FIFO safety (2), clock-gating correctness (1), protocol liveness (1).
- **6 Functional Covergroups**: Protocol switching, burst length distribution, address patterns, protocol transitions, operation-type cross, and power state correlation.

---

## ✅ Verification Methodology

The testbench (`TB.sv`) implements a professional UVM-style layered verification environment:

| Component | Description |
|:----------|:------------|
| **Generator** | Produces constrained-random and sequential traffic patterns with read-back verification |
| **Driver** | Converts transactions to pin-level stimulus with burst-type hints |
| **Monitor** | Observes DUT outputs with data integrity scoreboard and protocol transition tracking |
| **Functional Coverage** | 6 covergroups tracking protocol switches, burst lengths, address regions, transitions, operations, and power states |
| **SVA Assertions** | 8 properties: APB handshaking, AXI valid-ready (write+read), mutual exclusion, FIFO overflow/underflow, clock-gating correctness, protocol liveness |

---

## 📊 Results (Power & Area Analysis)

Synthesized using **Cadence Genus** with GSCL 90nm libraries:

### Power Comparison

| Configuration | Total Power | Reduction |
|:---|:---|:---|
| AXI-Only (Baseline) | 28.73 mW | — |
| **AXI-APB Hybrid** | **1.43 mW** | **95.02%** |

### Area Comparison

| Configuration | Total Area | Overhead |
|:---|:---|:---|
| AXI-Only | 91,967 µm² | — |
| AXI-APB Hybrid | 61,934 µm² | -32.7% |

### ML Classifier Efficiency

The traffic classifier adds only **1.2% area** (735 µm²) while enabling **95% power savings** — a power efficiency ratio of 37.1 µW per µm².

> **Conclusion:** Workload-aware protocol switching delivers 20.1x power reduction with no area penalty, making it ideal for power-critical SoC designs.

---

## 🔧 Technology Stack

| Tool | Purpose |
|:-----|:--------|
| **Cadence Genus** | RTL Synthesis (GSCL 90nm libraries) |
| **Cadence Xcelium** | SystemVerilog Simulation with SVA + Coverage |
| **Xilinx Vivado** | FPGA Synthesis & Prototyping (Artix-7) |
| **Scikit-Learn** | Decision Tree training & hardware LUT export |
| **SystemVerilog** | RTL Design & OOP Testbench |

---

## 🔨 Build Instructions

### Prerequisites
- Python 3.x with `scikit-learn`, `numpy`
- Cadence Xcelium (simulation)
- Cadence Genus (synthesis)

### Automated Pipeline (Makefile)

```bash
cd Code/Hybrid\ Low\ Power/

# Full pipeline: ML → Simulation → Synthesis
make all

# Individual steps:
make ml      # Train ML model, export and auto-copy SV LUT
make sim     # Run Xcelium simulation with assertions + coverage
make synth   # Run Genus synthesis, generate power/area/timing reports
```

### Manual Steps

```bash
# 1. Train ML and generate hardware LUT
cd "Ml Model/"
python DecisionTree.py

# 2. Simulate
cd "Code/Hybrid Low Power/"
bash xcelium_run.sh

# 3. Synthesize
genus -f genus_run.tcl
```

---

## 🚀 Future Scope

- **AHB Protocol Extension**: The parameterized `protocol_arbiter` module supports AHB activation via a single parameter change (`ENABLE_AHB=1`). The `protocol_t` enum includes `PROTO_AHB`, and the AHB-Lite stub (hsel, htrans, hwrite, hready, hresp) is conditionally compiled via a generate block. No existing AXI/APB code requires modification.

---

## 📂 Repository Structure

```text
ProjectSpace-8.0-/
├── Code/
│   ├── Hybrid Low Power/      # Main unified design
│   │   ├── Design.sv          # RTL: 6 modules + ML LUT + 8 SVA assertions
│   │   ├── TB.sv              # OOP testbench + 6 covergroups
│   │   ├── genus_run.tcl      # ASIC synthesis script (Cadence Genus)
│   │   ├── vivado_synth.tcl   # FPGA synthesis script (Xilinx Vivado)
│   │   ├── fpga_constraints.xdc # FPGA pin/timing constraints (Artix-7)
│   │   ├── xcelium_run.sh     # Simulation script (Cadence Xcelium)
│   │   ├── Makefile           # Automated ML → Sim → Synth pipeline
│   │   └── *.sdc              # ASIC timing constraints
│   └── Outputs Files/         # Synthesis reports
│       ├── Hybrid Reports.txt
│       └── AXI Reports.txt
├── Ml Model/                  # ML training & hardware export
│   ├── DecisionTree.py        # Scikit-Learn training + auto SV LUT export
│   ├── rule_based.py          # Rule-based verification baseline
│   ├── compare.py             # ML vs Rule comparison
│   ├── bridge_output.txt      # Input transaction data
│   ├── model_output.txt       # ML classification output
│   └── final_output.txt       # Rule-based output
├── Documentation/
├── Animation/
├── PPT/
├── Code/Reports.txt           # Comparative power & area analysis
├── Description
└── README.md
```