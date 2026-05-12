# Vivado FPGA Synthesis Guide

## Target Device
- **FPGA**: Xilinx Artix-7 (xc7a35tcpg236-1)
- **Purpose**: FPGA prototyping of the AXI-APB Hybrid Interface
- **Primary ASIC Flow**: Cadence Genus (90nm GSCL)

## Quick Start

### Option 1: Batch Mode (Command Line)
```bash
cd "Code/Hybrid Low Power/"
vivado -mode batch -source vivado_synth.tcl
```

### Option 2: Vivado GUI
1. Open Vivado
2. **Create Project** → Name: `hybrid_fpga`, Part: `xc7a35tcpg236-1`
3. **Add Sources** → Add `Design.sv` (do NOT add `TB.sv` — it contains non-synthesizable testbench constructs)
4. **Add Constraints** → Add `fpga_constraints.xdc`
5. **Set Top Module** → `top_memory_system`
6. **Run Synthesis** → Review utilization and timing reports

### Important Notes
- Only `Design.sv` is synthesizable. `TB.sv` contains SystemVerilog classes, mailboxes, and constrained randomization which are simulation-only constructs.
- The `cpu_if` interface is synthesized as individual ports by Vivado.
- The `bind` statement at the end of `Design.sv` is for simulation assertions only — Vivado will ignore it during synthesis.
- Clock constraint is set to 100 MHz (10ns period) in the XDC file. Adjust as needed for your target frequency.

## Generated Reports
After synthesis, the following reports are generated:
- `fpga_utilization.rep` — LUT, FF, BRAM usage
- `fpga_timing.rep` — Setup/hold timing summary
- `fpga_power.rep` — Estimated FPGA power consumption

## Files
| File | Purpose |
|:-----|:--------|
| `vivado_synth.tcl` | Batch synthesis script |
| `fpga_constraints.xdc` | Pin assignments + timing constraints (Artix-7) |
| `Design.sv` | Synthesizable RTL (all 6 modules) |
