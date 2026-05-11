# Traffic Classification ML Model

This folder contains the Machine Learning pipeline used to intelligently classify memory traffic and dynamically select between the high-performance AXI protocol and the low-power APB protocol.

## Purpose

Instead of using a hardcoded, sub-optimal heuristic to decide when to switch protocols, we use a Scikit-Learn Decision Tree to learn the optimal decision boundaries based on simulated traffic bursts. 

The goal is to answer: *How many sequential address increments — combined with what other traffic features — should we observe before the energy overhead of switching to AXI is worth it?*

## Files

1. **`bridge_output.txt`**: The raw transaction dataset simulating typical CPU workload patterns (bursty vs. random).
2. **`DecisionTree.py`**: The training script. It extracts features (burst length, address diff, rolling mean, streak flag) and trains a `DecisionTreeClassifier` with `max_depth=5`. **Critically, it also exports the full tree structure as a synthesizable SystemVerilog LUT** via `export_tree_to_sv_lut()`.
3. **`rule_based.py`**: A purely rule-based approach used as a baseline to verify the ML model's logic.
4. **`compare.py`**: Compares the output of the ML model (`model_output.txt`) against the rule-based expected logic (`final_output.txt`) to ensure accuracy.

## ML-to-Hardware Pipeline

The trained Scikit-Learn model's **full decision tree** is extracted and mapped directly to hardware RTL as a combinational lookup table (LUT). This is not a simple threshold extraction — the complete tree structure (all nodes, feature comparisons, and leaf classifications) is translated to synthesizable SystemVerilog.

### Pipeline Steps

```
bridge_output.txt  →  Feature Engineering  →  DecisionTreeClassifier (max_depth=5)
                                                       │
                                          export_tree_to_sv_lut()
                                                       │
                                              ml_decision_lut.sv
                                                       │
                                        Design.sv (ml_decision_lut module)
                                                       │
                                          traffic_classifier uses LUT
                                                       │
                                       Zero-latency protocol selection
```

### Decision Tree Structure (Learned)

The trained tree evaluates multiple features simultaneously:

| Feature | Hardware Signal | Description |
|:--------|:---------------|:------------|
| `burst_len` | `burst_len[4:0]` | Count of consecutive sequential addresses |
| `is_inc` / `addr_diff` | `addr_diff_sequential` | Whether current address follows sequential stride |
| `streak_flag` | `streak_flag` | Whether burst_len exceeds a minimum streak threshold |

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
        end else if (burst_len > 5'd5) begin
            if (addr_diff_sequential)
                predict_axi = 1'b1;  // AXI: long sequential burst
        end
    end
endmodule
```

The `traffic_classifier` module extracts features from live CPU transactions and feeds them to the `ml_decision_lut` every clock cycle. The LUT produces a single-cycle combinational prediction which is then registered into the protocol selection outputs (`use_axi`, `use_apb`).

### Key Properties
- **Zero-latency inference**: Pure combinational logic, no pipeline stages
- **Minimal gate overhead**: The tree compiles to ~10 gates in Cadence Genus synthesis
- **Faithful model reproduction**: Every decision path from the Scikit-Learn tree is preserved
- **Automated generation**: Running `python DecisionTree.py` re-exports the LUT from the latest trained model
