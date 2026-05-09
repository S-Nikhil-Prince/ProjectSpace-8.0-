def read_file(file):
    with open(file, 'r') as f:
        return f.readlines()

ml = read_file("model_output.txt")
rule = read_file("final_output.txt")

print("Comparison:\n")

for m, r in zip(ml, rule):
    if m.strip() == r.strip():
        print(f"✔ MATCH: {m.strip()}")
    else:
        print(f"❌ ML: {m.strip()} | RULE: {r.strip()}")