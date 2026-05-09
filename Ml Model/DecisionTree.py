import numpy as np
from sklearn.tree import DecisionTreeClassifier
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
        
        # 🔥 IMPORTANT: enforce burst rule
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
# MAIN
# ----------------------------
def main():
    input_file = "bridge_output.txt"
    output_file = "model_output.txt"
    
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
    
    model = train_model(X, y)
    
    classify_and_write(transactions, model, output_file)
    
    print("Output written to model_output.txt")


if __name__ == "__main__":
    main()