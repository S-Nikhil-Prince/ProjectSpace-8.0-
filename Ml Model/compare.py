import os
import sys

def read_file(file):
    if not os.path.exists(file):
        print(f"ERROR: File '{file}' not found.")
        sys.exit(1)
    with open(file, 'r') as f:
        return f.readlines()

def main():
    ml_file = "model_output.txt"
    rule_file = "final_output.txt"
    
    ml = read_file(ml_file)
    rule = read_file(rule_file)
    
    if len(ml) == 0 or len(rule) == 0:
        print("ERROR: One or both output files are empty.")
        sys.exit(1)
    
    matches = 0
    mismatches = 0
    
    print("Comparison:\n")
    
    for m, r in zip(ml, rule):
        if m.strip() == r.strip():
            matches += 1
            print(f"✔ MATCH: {m.strip()}")
        else:
            mismatches += 1
            print(f"❌ ML: {m.strip()} | RULE: {r.strip()}")
    
    # Check for length mismatch
    if len(ml) != len(rule):
        print(f"\n⚠ WARNING: Output length mismatch — ML has {len(ml)} segments, Rule has {len(rule)} segments")
    
    print(f"\nSummary: {matches} matches, {mismatches} mismatches out of {matches + mismatches} segments")
    
    if mismatches == 0:
        print("✅ ML model output matches rule-based baseline perfectly")
    else:
        print(f"⚠ {mismatches} discrepancies found — review threshold alignment")

if __name__ == "__main__":
    main()