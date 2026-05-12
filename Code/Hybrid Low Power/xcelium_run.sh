#!/bin/bash
# ============================================================
# Xcelium Simulation Script
# ============================================================
# Runs SystemVerilog simulation with:
#   - Full SVA assertion checking (-assert)
#   - Functional coverage collection (-coverage all)
#   - Read/write/connectivity access for debug (-access +rwc)
#   - Simulation log saved to simulation_log.txt
# ============================================================

set -e

echo "============================================================"
echo "  Running Cadence Xcelium Simulation"
echo "============================================================"

xrun -sv -access +rwc -assert -coverage all -covoverwrite \
    Design.sv TB.sv 2>&1 | tee simulation_log.txt

echo ""
echo "============================================================"
echo "  Simulation complete. Log saved to simulation_log.txt"
echo "============================================================"