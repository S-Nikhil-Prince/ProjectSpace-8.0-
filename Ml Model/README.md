# Traffic Classification ML Model

This folder contains the Machine Learning pipeline used to intelligently classify memory traffic and dynamically select between the high-performance AXI protocol and the low-power APB protocol.

## Purpose

Instead of using a hardcoded, sub-optimal heuristic to decide when to switch protocols, we use a Scikit-Learn Decision Tree to learn the optimal threshold based on simulated traffic bursts. 

The goal is to answer: *How many sequential address increments should we observe before the energy overhead of switching to AXI is worth it?*

## Files

1. **`bridge_output.txt`**: The raw transaction dataset simulating typical CPU workload patterns (bursty vs. random).
2. **`DecisionTree.py`**: The training script. It extracts features (burst length, address diff, rolling mean) and trains a `DecisionTreeClassifier` with `max_depth=5`.
3. **`rule_based.py`**: A purely rule-based approach used as a baseline to verify the ML model's logic.
4. **`compare.py`**: Compares the output of the ML model (`model_output.txt`) against the rule-based expected logic (`final_output.txt`) to ensure accuracy.

## Hardware Inference Bridge

The trained Scikit-Learn model's decision logic was extracted and mapped directly to hardware RTL. 

The model learned that a `burst_len >= 5` is the optimal switching point for this workload. This learned parameter is injected directly into our SystemVerilog architecture as a synthesis parameter:

```systemverilog
// In Design.sv (Traffic Classifier)
parameter BURST_THRESHOLD = 5;

// Hardware inference rule replacing Scikit-Learn prediction
if (burst_len >= BURST_THRESHOLD) begin
    use_axi = 1;
    use_apb = 0;
end
```

By doing this, we achieve **real-time ML inference** with zero clock-cycle latency and minimal gate overhead!
