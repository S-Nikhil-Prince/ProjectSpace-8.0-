# ----------------------------
# Parse each line safely
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
        addr = int(parts[1].split('=')[1].replace('h', ''), 16)
        data = int(parts[2].split('=')[1].replace('h', ''), 16)
        
        return clk, addr, data
    
    except:
        return None


# ----------------------------
# Rule-based classification
# ----------------------------
def classify_transactions(transactions):
    results = []
    
    start_idx = 0
    i = 1
    
    while i < len(transactions):
        burst_len = 1
        
        # Check consecutive increment (+4)
        while (i < len(transactions) and 
               transactions[i][1] == transactions[i-1][1] + 4):
            burst_len += 1
            i += 1
        
        start_clk = transactions[start_idx][0]
        end_clk = transactions[i-1][0]
        
        if burst_len > 5:
            typ = "AXI"
        else:
            typ = "APB"
        
        results.append((start_clk, end_clk, typ))
        
        start_idx = i
        i += 1
    
    return results


# ----------------------------
# Write output
# ----------------------------
def write_output(results, output_file):
    with open(output_file, 'w') as f:
        for start, end, typ in results:
            f.write(f"clk {start} to clk {end} : {typ}\n")


# ----------------------------
# MAIN
# ----------------------------
def main():
    input_file = "bridge_output.txt"
    output_file = "final_output.txt"
    
    with open(input_file, 'r') as f:
        lines = f.readlines()
    
    transactions = []
    for line in lines:
        parsed = parse_line(line)
        if parsed:
            transactions.append(parsed)
    
    if len(transactions) < 2:
        print("Not enough valid transactions.")
        return
    
    results = classify_transactions(transactions)
    write_output(results, output_file)
    
    print("✅ Rule-based output written to final_output.txt")


if __name__ == "__main__":
    main()