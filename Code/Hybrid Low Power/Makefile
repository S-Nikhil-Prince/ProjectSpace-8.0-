# ============================================================
# Makefile: Automated ML-to-Hardware Build Pipeline
# ============================================================
# This Makefile automates the full design flow:
#   1. ML Training → LUT Generation → Auto-copy to RTL
#   2. Simulation (Cadence Xcelium)
#   3. Synthesis (Cadence Genus)
#
# Usage:
#   make all       - Run full pipeline (ML + Sim + Synth)
#   make ml        - Train ML model and generate hardware LUT
#   make sim       - Run Xcelium simulation
#   make synth     - Run Genus synthesis
#   make clean     - Remove generated files
# ============================================================

# Directories
ML_DIR      = ../../Ml\ Model
DESIGN_DIR  = .
REPORT_DIR  = ../Outputs\ Files

# Tools
PYTHON      = python3
XRUN        = xrun
GENUS       = genus

# Files
DESIGN_SRC  = Design.sv
TB_SRC      = TB.sv
TCL_SCRIPT  = genus_run.tcl
SIM_LOG     = simulation_log.txt

# ============================================================
# TARGETS
# ============================================================

.PHONY: all ml sim synth clean help

help:
	@echo "============================================================"
	@echo "  AXI-APB Hybrid Interface — Build Targets"
	@echo "============================================================"
	@echo "  make ml      - Train ML model, export SV LUT, auto-copy"
	@echo "  make sim     - Run Xcelium simulation with coverage"
	@echo "  make synth   - Run Genus RTL synthesis"
	@echo "  make all     - Full pipeline: ML → Sim → Synth"
	@echo "  make clean   - Remove generated artifacts"
	@echo "============================================================"

# Full pipeline
all: ml sim synth
	@echo ""
	@echo "============================================================"
	@echo "  FULL PIPELINE COMPLETE"
	@echo "============================================================"

# Step 1: ML Training + LUT Export + Auto-copy to Design
ml:
	@echo ""
	@echo "============================================================"
	@echo "  STEP 1: ML Training & Hardware LUT Generation"
	@echo "============================================================"
	cd $(ML_DIR) && $(PYTHON) DecisionTree.py --design-dir "$(abspath $(DESIGN_DIR))"
	@echo "  ✅ ML LUT synchronized with Design.sv"

# Step 2: Xcelium Simulation
sim:
	@echo ""
	@echo "============================================================"
	@echo "  STEP 2: Xcelium Simulation (assertions + coverage)"
	@echo "============================================================"
	$(XRUN) -sv -access +rwc -assert -coverage all -covoverwrite \
		$(DESIGN_SRC) $(TB_SRC) 2>&1 | tee $(SIM_LOG)
	@echo "  ✅ Simulation log saved to $(SIM_LOG)"

# Step 3: Genus Synthesis
synth:
	@echo ""
	@echo "============================================================"
	@echo "  STEP 3: Genus RTL Synthesis"
	@echo "============================================================"
	$(GENUS) -f $(TCL_SCRIPT)
	@echo "  ✅ Synthesis reports generated"

# Cleanup
clean:
	@rm -f $(SIM_LOG)
	@rm -f ml_decision_lut.sv
	@rm -f xcelium.d -rf
	@rm -f *.log *.rep *.key
	@echo "  Cleaned generated files"
