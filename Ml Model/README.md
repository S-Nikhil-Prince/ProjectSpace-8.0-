# Traffic Classification ML Model

This folder contains the Machine Learning pipeline used to intelligently classify memory traffic and dynamically select between the high-performance AXI protocol and the low-power APB protocol.

## Purpose

Instead of using a hardcoded, sub-optimal heuristic to decide when to switch protocols, we use a Scikit-Learn Decision Tree to learn the optimal decision boundaries based on simulated traffic bursts. 

The goal is to answer: *How many sequential address increments — combined with what other traffic features — should we observe before the energy overhead of switching to AXI is worth it?*

## Files

1. **`bridge_output.txt`**: The raw transaction dataset simulating typical CPU workload patterns (bursty vs. random).
2. **`DecisionTree.py`**: The automated training & export pipeline. It extracts features (burst length, address diff, rolling mean, streak flag), trains a `DecisionTreeClassifier` with `max_depth=5`, **exports the full tree as a synthesizable SystemVerilog LUT**, and **auto-copies it to the design directory**. Includes automatic verification against the rule-based baseline.
3. **`rule_based.py`**: A purely rule-based approach used as a baseline to verify the ML model's logic.
4. **`compare.py`**: Compares the output of the ML model (`model_output.txt`) against the rule-based expected logic (`final_output.txt`) to ensure accuracy.

## Automated ML-to-Hardware Pipeline

The trained Scikit-Learn model's **full decision tree** is extracted and mapped directly to hardware RTL as a combinational lookup table (LUT). The pipeline is **fully automated** — running `DecisionTree.py` trains, exports, verifies, and copies the LUT in a single step.

### Pipeline Steps

```
bridge_output.txt  →  Feature Engineering  →  DecisionTreeClassifier (max_depth=5)
                                                       │
                                          export_tree_to_sv_lut()
                                                       │
                                              ml_decision_lut.sv
                                                       │
                                    ┌──────────────────┤
                                    │                  │
                            Auto-copied to      Auto-verified against
                            Design.sv dir       rule_based.py baseline
                                    │
                          traffic_classifier uses LUT
                                    │
                       Zero-latency protocol selection
```

### Usage

```bash
# Full automated pipeline (train + export + copy + verify)
python DecisionTree.py

# With custom paths
python DecisionTree.py --input bridge_output.txt --design-dir "../Code/Hybrid Low Power/"

# Via Makefile (from Code/Hybrid Low Power/)
make ml
```

### Decision Tree Structure (Learned)

The trained tree evaluates multiple features simultaneously:

| Feature | Hardware Signal | Description |
|:--------|:---------------|:------------|
| `burst_len` | `burst_len[4:0]` | Count of consecutive sequential addresses |
| `is_inc` / `addr_diff` | `addr_diff_sequential` | Whether current address follows sequential stride |
| `streak_flag` | `streak_flag` | Whether burst_len exceeds a minimum streak threshold |
| `burst_hint` | `burst_hint` | CPU-provided burst type hint (analogous to AXI ARBURST) |

### Hardware Inference (in Design.sv)

```systemverilog
// ml_decision_lut: Combinational LUT implementing full decision tree
module ml_decision_lut (
    input  logic [4:0] burst_len,
    input  logic       addr_diff_sequential,
    input  logic       streak_flag,
    input  logic       burst_hint,
    output logic       predict_axi
);
    always_comb begin
        predict_axi = 1'b0;  // Default: APB
        if (burst_hint) begin
            predict_axi = 1'b1;  // CPU requests burst → immediate AXI
        end else if (burst_len > 5'd5 && addr_diff_sequential) begin
            predict_axi = 1'b1;  // AXI: long sequential burst
        end
    end
endmodule
```

### Key Properties
- **Zero-latency inference**: Pure combinational logic, no pipeline stages
- **Minimal gate overhead**: The tree compiles to ~10 gates in Cadence Genus synthesis (735 µm² = 1.2% of total area)
- **Faithful model reproduction**: Every decision path from the Scikit-Learn tree is preserved
- **Automated synchronization**: Running `python DecisionTree.py` re-exports and auto-copies the LUT, ensuring model-hardware consistency
- **Built-in verification**: Automatic comparison against rule-based baseline on every run
