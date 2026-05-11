import numpy as np
from sklearn.tree import DecisionTreeClassifier, export_text
from sklearn.metrics import accuracy_score

# ----------------------------
# Parse safely
# ----------------------------
def parse_line(line):
    line = line.strip()
    if not line:
        return None
    
    parts = line.split()
    if len(parts) < 3:
        return None
    
    try:
        clk = int(parts[0].split('=')[1])
        addr = int(parts[1].split('=')[1].replace('h',''), 16)
        data = int(parts[2].split('=')[1].replace('h',''), 16)
        return clk, addr, data
    except:
        return None


# ----------------------------
# Feature Engineering
# ----------------------------
def extract_features(transactions):
    features = []
    labels = []
    
    burst_len = 1
    diffs = []
    
    for i in range(1, len(transactions)):
        prev_addr = transactions[i-1][1]
        curr_addr = transactions[i][1]
        
        diff = curr_addr - prev_addr
        diffs.append(diff)
        
        if diff == 4:
            burst_len += 1
            is_inc = 1
        else:
            burst_len = 1
            is_inc = 0
        
        # rolling mean of last 3 diffs
        last_diffs = diffs[-3:]
        rolling_mean = sum(last_diffs) / len(last_diffs)
        
        streak_flag = 1 if burst_len > 2 else 0
        
        features.append([diff, is_inc, burst_len, rolling_mean, streak_flag])
        
        # Label (your rule)
        labels.append(1 if burst_len > 5 else 0)
    
    return np.array(features), np.array(labels)


# ----------------------------
# Train model
# ----------------------------
def train_model(X, y):
    model = DecisionTreeClassifier(max_depth=5)
    model.fit(X, y)
    
    preds = model.predict(X)
    acc = accuracy_score(y, preds)
    
    print(f"Model training accuracy: {acc*100:.2f}%")
    
    return model


# ----------------------------
# Predict + smooth segmentation
# ----------------------------
def classify_and_write(transactions, model, output_file):
    results = []
    
    start_clk = transactions[0][0]
    prev_addr = transactions[0][1]
    
    burst_len = 1
    prev_type = "APB"  # start safe
    
    for i in range(1, len(transactions)):
        clk, addr, _ = transactions[i]
        
        diff = addr - prev_addr
        
        if diff == 4:
            burst_len += 1
        else:
            burst_len = 1
        
        # ML prediction
        is_inc = 1 if diff == 4 else 0
        streak_flag = 1 if burst_len > 2 else 0
        
        feature = np.array([[diff, is_inc, burst_len, diff, streak_flag]])
        pred = model.predict(feature)[0]
        
        # Enforce burst rule
        if burst_len > 5:
            current_type = "AXI"
        else:
            current_type = "APB"
        
        # segment detection
        if current_type != prev_type:
            end_clk = transactions[i-1][0]
            results.append((start_clk, end_clk, prev_type))
            start_clk = clk
        
        prev_type = current_type
        prev_addr = addr
    
    # last segment
    end_clk = transactions[-1][0]
    results.append((start_clk, end_clk, prev_type))
    
    with open(output_file, 'w') as f:
        for s, e, t in results:
            f.write(f"clk {s} to clk {e} : {t}\n")


# ----------------------------
# Export Decision Tree to SystemVerilog LUT
# ----------------------------
# This function extracts the trained tree's structure and
# generates a synthesizable SystemVerilog module that
# replicates the learned decision logic as a combinational
# lookup table (LUT). This bridges the ML-to-hardware gap.
# ----------------------------
def export_tree_to_sv_lut(model, feature_names, output_file="ml_decision_lut.sv"):
    """
    Export the trained DecisionTreeClassifier as a SystemVerilog
    combinational LUT module for direct hardware synthesis.
    
    The generated module is a pure combinational block that
    evaluates the same features the tree was trained on and
    produces a 1-bit predict_axi output.
    """
    tree = model.tree_
    
    print("\n" + "="*60)
    print("  DECISION TREE → HARDWARE LUT EXPORT")
    print("="*60)
    
    # Print the text representation of the tree
    tree_text = export_text(model, feature_names=feature_names)
    print("\nTrained Decision Tree Structure:")
    print(tree_text)
    
    # Extract key thresholds from the tree
    print("\nExtracted Hardware Parameters:")
    print(f"  - Number of nodes: {tree.node_count}")
    print(f"  - Max depth: {model.get_depth()}")
    print(f"  - Number of leaves: {model.get_n_leaves()}")
    
    # Walk the tree and extract decision rules
    rules = []
    _extract_rules(tree, 0, [], feature_names, rules)
    
    print(f"\nDecision Rules for AXI selection (predict=1):")
    axi_rules = [r for r in rules if r['class'] == 1]
    for rule in axi_rules:
        conditions = " AND ".join(rule['conditions'])
        print(f"  IF {conditions} → AXI")
    
    print(f"\nDecision Rules for APB selection (predict=0):")
    apb_rules = [r for r in rules if r['class'] == 0]
    for rule in apb_rules:
        conditions = " AND ".join(rule['conditions'])
        print(f"  IF {conditions} → APB")
    
    # Generate SystemVerilog code
    sv_code = _generate_sv_lut(rules, feature_names)
    
    with open(output_file, 'w') as f:
        f.write(sv_code)
    
    print(f"\n✅ SystemVerilog LUT written to: {output_file}")
    print("="*60)
    
    return rules


def _extract_rules(tree, node_id, conditions, feature_names, rules):
    """Recursively extract decision rules from the tree."""
    left = tree.children_left[node_id]
    right = tree.children_right[node_id]
    
    if left == right:  # Leaf node
        class_id = int(np.argmax(tree.value[node_id]))
        rules.append({
            'conditions': list(conditions),
            'class': class_id,
            'samples': int(tree.n_node_samples[node_id])
        })
        return
    
    feature = feature_names[tree.feature[node_id]]
    threshold = tree.threshold[node_id]
    
    # Left branch: feature <= threshold
    left_cond = f"{feature} <= {threshold:.1f}"
    _extract_rules(tree, left, conditions + [left_cond], feature_names, rules)
    
    # Right branch: feature > threshold
    right_cond = f"{feature} > {threshold:.1f}"
    _extract_rules(tree, right, conditions + [right_cond], feature_names, rules)


def _generate_sv_lut(rules, feature_names):
    """Generate SystemVerilog LUT code from extracted rules."""
    sv = []
    sv.append("// ============================================================")
    sv.append("// AUTO-GENERATED: ML Decision Tree LUT")
    sv.append("// Generated by DecisionTree.py export_tree_to_sv_lut()")
    sv.append("// ============================================================")
    sv.append("// This module was automatically generated from a trained")
    sv.append("// Scikit-Learn DecisionTreeClassifier. It implements the")
    sv.append("// learned decision boundaries as synthesizable combinational")
    sv.append("// logic for zero-latency protocol selection.")
    sv.append("// ============================================================")
    sv.append("")
    sv.append("module ml_decision_lut (")
    sv.append("    input  logic [4:0] burst_len,")
    sv.append("    input  logic       addr_diff_sequential,")
    sv.append("    input  logic       streak_flag,")
    sv.append("    output logic       predict_axi")
    sv.append(");")
    sv.append("")
    sv.append("    always_comb begin")
    sv.append("        predict_axi = 1'b0;  // Default: APB (low power)")
    sv.append("")
    
    # Generate conditions for AXI selection
    axi_rules = [r for r in rules if r['class'] == 1]
    for i, rule in enumerate(axi_rules):
        prefix = "        if" if i == 0 else "        else if"
        conditions = _translate_conditions(rule['conditions'])
        sv.append(f"{prefix} ({conditions}) begin")
        sv.append(f"            predict_axi = 1'b1;  // AXI (high throughput)")
        sv.append(f"        end")
    
    sv.append("    end")
    sv.append("")
    sv.append("endmodule")
    
    return "\n".join(sv)


def _translate_conditions(conditions):
    """Translate ML conditions to SystemVerilog syntax."""
    sv_conditions = []
    for cond in conditions:
        # Map feature names to SystemVerilog signal names
        cond = cond.replace("addr_diff", "addr_diff_sequential")
        cond = cond.replace("is_inc", "addr_diff_sequential")
        
        if "burst_len" in cond:
            # Extract threshold and convert to SV comparison
            if "<=" in cond:
                parts = cond.split("<=")
                val = int(float(parts[1].strip()))
                sv_conditions.append(f"burst_len <= 5'd{val}")
            elif ">" in cond:
                parts = cond.split(">")
                val = int(float(parts[1].strip()))
                sv_conditions.append(f"burst_len > 5'd{val}")
        elif "streak_flag" in cond:
            if "<=" in cond:
                sv_conditions.append("!streak_flag")
            else:
                sv_conditions.append("streak_flag")
        elif "addr_diff_sequential" in cond or "is_inc" in cond:
            if "<=" in cond:
                sv_conditions.append("!addr_diff_sequential")
            else:
                sv_conditions.append("addr_diff_sequential")
    
    return " && ".join(sv_conditions) if sv_conditions else "1'b0"


# ----------------------------
# MAIN
# ----------------------------
def main():
    input_file = "bridge_output.txt"
    output_file = "model_output.txt"
    sv_output_file = "ml_decision_lut.sv"
    
    with open(input_file, 'r') as f:
        lines = f.readlines()
    
    transactions = []
    for line in lines:
        parsed = parse_line(line)
        if parsed:
            transactions.append(parsed)
    
    if len(transactions) < 2:
        print("Not enough data")
        return
    
    X, y = extract_features(transactions)
    
    feature_names = ["addr_diff", "is_inc", "burst_len", "rolling_mean", "streak_flag"]
    
    model = train_model(X, y)
    
    classify_and_write(transactions, model, output_file)
    
    print("Output written to model_output.txt")
    
    # Export trained tree to SystemVerilog LUT for hardware synthesis
    export_tree_to_sv_lut(model, feature_names, sv_output_file)


if __name__ == "__main__":
    main()