class cpu_transaction;

    rand bit [7:0]  addr;
    rand bit [31:0] wdata;

    rand bit write;
    rand bit read;

    rand bit sequential;

    int burst_id;
    int beat_id;
    int total_beats;

    constraint addr_range {
        addr inside {[0:191]};
    }

    constraint operation_valid {
        (write ^ read) == 1;
    }

endclass


class generator;

    cpu_transaction tr;

    mailbox #(cpu_transaction) gen2drv;

    function new(mailbox #(cpu_transaction) mb);
        gen2drv = mb;
    endfunction

    task run();

        integer i;
        integer mode;
        integer seq_count;
        integer burst_no;
        integer beat;
        
        int stored_addrs[$];
        int stored_data[$];

        i = 0;
        burst_no = 0;

      repeat(11)
        begin

            mode = $urandom_range(0,1);

            seq_count = $urandom_range(4,8);

            for(beat = 0; beat < seq_count; beat++)
            begin

                tr = new();

                assert(tr.randomize());

                tr.burst_id   = burst_no;
                tr.beat_id    = beat;
                tr.total_beats = seq_count;

                // =========================
                // Sequential AXI Traffic
                // =========================
                if(mode)
                begin

                    tr.addr = i;
                    tr.sequential = 1;

                    i++;

                end

                // =========================
                // Random APB Traffic
                // =========================
                else
                begin

                    tr.addr = $urandom_range(0,63);
                    tr.sequential = 0;

                end

                tr.write = 1;
                tr.read  = 0;
                
                stored_addrs.push_back(tr.addr);
                stored_data.push_back(tr.wdata);

                gen2drv.put(tr);

            end

            burst_no++;
            
            // NOW READ THEM BACK
            for(beat = 0; beat < seq_count; beat++)
            begin
                tr = new();
                tr.burst_id   = burst_no;
                tr.beat_id    = beat;
                tr.total_beats = seq_count;
                tr.addr = stored_addrs.pop_front();
                tr.wdata = 0;
                tr.write = 0;
                tr.read = 1;
                if(mode) tr.sequential = 1; else tr.sequential = 0;

                gen2drv.put(tr);
            end
            
            burst_no++;

        end

    endtask

endclass


class driver;

    virtual cpu_if vif;

    mailbox #(cpu_transaction) gen2drv;

    function new(
        virtual cpu_if vif,
        mailbox #(cpu_transaction) mb
    );

        this.vif = vif;
        gen2drv = mb;

    endfunction


    task run();

        cpu_transaction tr;

        forever
        begin

            gen2drv.get(tr);

            @(posedge vif.clk);

            vif.addr  <= tr.addr;
            vif.wdata <= tr.wdata;

            // ====================================
            // CPU BURST-TYPE HINT (like AXI ARBURST)
            // ====================================
            vif.burst_hint <= tr.sequential;

            vif.write <= tr.write;
            vif.read  <= tr.read;

            // ====================================
            // BURST TRACKING INFO
            // ====================================

            vif.burst_id     <= tr.burst_id;
            vif.beat_id      <= tr.beat_id;
            vif.total_beats  <= tr.total_beats;

            @(posedge vif.clk);

            vif.write <= 0;
            vif.read  <= 0;

            repeat(2)
                @(posedge vif.clk);

        end

    endtask

endclass


// ============================================================
// FUNCTIONAL COVERAGE
// ============================================================
// Covergroups measure completeness of verification across:
//   1. Protocol switching transitions (APB→AXI, AXI→APB)
//   2. Burst length distribution
//   3. Address access patterns (sequential vs random)
//   4. Protocol-operation cross coverage
// ============================================================

class functional_coverage;

    virtual cpu_if vif;

    // State tracking for transition coverage
    logic prev_use_axi;
    logic prev_use_apb;

    // --------------------------------------------------------
    // Covergroup 1: Protocol Switching Transitions
    // --------------------------------------------------------
    covergroup cg_protocol_switch @(posedge vif.clk);
        option.per_instance = 1;
        option.name = "Protocol_Switch_Coverage";

        cp_use_axi : coverpoint vif.use_axi {
            bins axi_active   = {1};
            bins axi_inactive = {0};
        }

        cp_use_apb : coverpoint vif.use_apb {
            bins apb_active   = {1};
            bins apb_inactive = {0};
        }

        // Cross coverage: ensure we see both protocols activated
        cx_protocol_select : cross cp_use_axi, cp_use_apb {
            // Valid states: AXI active + APB inactive, or APB active + AXI inactive
            bins axi_mode = binsof(cp_use_axi.axi_active) && binsof(cp_use_apb.apb_inactive);
            bins apb_mode = binsof(cp_use_axi.axi_inactive) && binsof(cp_use_apb.apb_active);
            // Illegal: both active simultaneously (mutual exclusion)
            illegal_bins both_active = binsof(cp_use_axi.axi_active) && binsof(cp_use_apb.apb_active);
        }
    endgroup

    // --------------------------------------------------------
    // Covergroup 2: Burst Length Distribution
    // --------------------------------------------------------
    covergroup cg_burst_length @(posedge vif.clk);
        option.per_instance = 1;
        option.name = "Burst_Length_Coverage";

        cp_continuous_count : coverpoint vif.continuous_count {
            bins idle           = {0};
            bins short_burst    = {[1:3]};
            bins medium_burst   = {[4:5]};       // Near ML threshold
            bins threshold_hit  = {[6:8]};       // Above ML threshold → AXI
            bins long_burst     = {[9:15]};
            bins very_long      = {[16:$]};
        }
    endgroup

    // --------------------------------------------------------
    // Covergroup 3: Address Access Patterns
    // --------------------------------------------------------
    covergroup cg_address_pattern @(posedge vif.clk);
        option.per_instance = 1;
        option.name = "Address_Pattern_Coverage";

        cp_sequential : coverpoint vif.sequential_access {
            bins sequential = {1};
            bins random_    = {0};
        }

        cp_random : coverpoint vif.random_access {
            bins random_active   = {1};
            bins random_inactive = {0};
        }

        cp_addr_region : coverpoint vif.addr {
            bins low_addr   = {[0:63]};
            bins mid_addr   = {[64:127]};
            bins high_addr  = {[128:191]};
        }

        // Cross: address region vs protocol type
        cx_addr_protocol : cross cp_addr_region, cp_sequential {
            bins seq_low  = binsof(cp_addr_region.low_addr) && binsof(cp_sequential.sequential);
            bins seq_mid  = binsof(cp_addr_region.mid_addr) && binsof(cp_sequential.sequential);
            bins seq_high = binsof(cp_addr_region.high_addr) && binsof(cp_sequential.sequential);
            bins rnd_low  = binsof(cp_addr_region.low_addr) && binsof(cp_sequential.random_);
            bins rnd_mid  = binsof(cp_addr_region.mid_addr) && binsof(cp_sequential.random_);
            bins rnd_high = binsof(cp_addr_region.high_addr) && binsof(cp_sequential.random_);
        }
    endgroup

    // --------------------------------------------------------
    // Covergroup 4: Protocol Transition Events
    // --------------------------------------------------------
    covergroup cg_transitions @(posedge vif.clk);
        option.per_instance = 1;
        option.name = "Protocol_Transition_Coverage";

        // Track transitions: APB→AXI and AXI→APB
        cp_transition : coverpoint {prev_use_axi, vif.use_axi} {
            bins apb_to_axi = {2'b01};  // was APB (0), now AXI (1)
            bins axi_to_apb = {2'b10};  // was AXI (1), now APB (0)
            bins stay_apb   = {2'b00};  // remains APB
            bins stay_axi   = {2'b11};  // remains AXI
        }
    endgroup

    // --------------------------------------------------------
    // Covergroup 5: Operation Type Coverage
    // --------------------------------------------------------
    covergroup cg_operations @(posedge vif.clk);
        option.per_instance = 1;
        option.name = "Operation_Type_Coverage";

        cp_write : coverpoint vif.write {
            bins active   = {1};
            bins inactive = {0};
        }

        cp_read : coverpoint vif.read {
            bins active   = {1};
            bins inactive = {0};
        }

        cp_protocol : coverpoint vif.use_axi {
            bins axi = {1};
            bins apb = {0};
        }

        // Cross: operation type vs protocol
        cx_op_proto : cross cp_write, cp_read, cp_protocol {
            bins axi_write = binsof(cp_write.active) && binsof(cp_read.inactive) && binsof(cp_protocol.axi);
            bins axi_read  = binsof(cp_write.inactive) && binsof(cp_read.active) && binsof(cp_protocol.axi);
            bins apb_write = binsof(cp_write.active) && binsof(cp_read.inactive) && binsof(cp_protocol.apb);
            bins apb_read  = binsof(cp_write.inactive) && binsof(cp_read.active) && binsof(cp_protocol.apb);
        }
    endgroup

    function new(virtual cpu_if vif);
        this.vif = vif;
        prev_use_axi = 0;
        prev_use_apb = 1;
        cg_protocol_switch = new();
        cg_burst_length = new();
        cg_address_pattern = new();
        cg_transitions = new();
        cg_operations = new();
    endfunction

    task run();
        forever begin
            @(posedge vif.clk);
            prev_use_axi = vif.use_axi;
            prev_use_apb = vif.use_apb;
        end
    endtask

    function void report();
        $display("");
        $display("====================================================");
        $display("          FUNCTIONAL COVERAGE REPORT                 ");
        $display("====================================================");
        $display("Protocol Switch Coverage : %0.2f%%", cg_protocol_switch.get_inst_coverage());
        $display("Burst Length Coverage    : %0.2f%%", cg_burst_length.get_inst_coverage());
        $display("Address Pattern Coverage : %0.2f%%", cg_address_pattern.get_inst_coverage());
        $display("Transition Coverage      : %0.2f%%", cg_transitions.get_inst_coverage());
        $display("Operation Type Coverage  : %0.2f%%", cg_operations.get_inst_coverage());
        $display("====================================================");
    endfunction

endclass


class monitor;

    virtual cpu_if vif;

    bit [31:0] expected_mem [0:255];

    integer axi_pass;
    integer axi_fail;

    integer bridge_pass;
    integer bridge_fail;

    string current_path;

    integer current_burst;

    // Protocol switch counters
    integer apb_to_axi_count;
    integer axi_to_apb_count;
    logic   prev_use_axi;

    function new(virtual cpu_if vif);

        this.vif = vif;

        axi_pass = 0;
        axi_fail = 0;
        bridge_pass = 0;
        bridge_fail = 0;
        current_burst = -1;
        apb_to_axi_count = 0;
        axi_to_apb_count = 0;
        prev_use_axi = 0;

    endfunction


    task run();

        forever
        begin

            @(posedge vif.clk);

            // ====================================
            // PROTOCOL TRANSITION TRACKING
            // ====================================
            if (vif.use_axi && !prev_use_axi) begin
                apb_to_axi_count++;
                $display("[%0t] >>> PROTOCOL SWITCH: APB -> AXI (transition #%0d)", $time, apb_to_axi_count);
            end else if (!vif.use_axi && prev_use_axi) begin
                axi_to_apb_count++;
                $display("[%0t] >>> PROTOCOL SWITCH: AXI -> APB (transition #%0d)", $time, axi_to_apb_count);
            end
            prev_use_axi = vif.use_axi;

            // ====================================
            // NEW BURST DETECTED
            // ====================================

            if(vif.write && (vif.burst_id != current_burst))
            begin

                current_burst = vif.burst_id;

                $display("");
                $display("====================================================");
                $display("BURST %0d", vif.burst_id);

                $display("Beats      = %0d",
                         vif.total_beats);

                if(vif.use_axi)
                    $display("Addr style =    SEQUENTIAL (AXI path)");
                else
                    $display("Addr style = RANDOM (APB path)");

                $display("====================================================");

            end

            // ====================================
            // WRITE MONITORING
            // ====================================

            if(vif.write)
            begin

                if(vif.use_axi)
                    current_path = "AXI";
                else
                    current_path = "APB";

                expected_mem[vif.addr] = vif.wdata;

              $display("[%0t] WRITE beat=%0d path=%0s addr=%0h data=%0h",
                         $time,
                         vif.beat_id,
                         current_path,
                         vif.addr,
                         vif.wdata);

            end

            // ====================================
            // READ MONITORING
            // ====================================

            if(vif.read)
            begin

                if(vif.use_axi)
                    current_path = "AXI";
                else
                    current_path = "APB";

                if(vif.rdata == expected_mem[vif.addr])
                begin

                    if(vif.use_axi)
                        axi_pass++;
                    else
                        bridge_pass++;

                    $display("[%0t] READ  beat=%0d path=%6s addr=%0h data=%0h (expected=%0h)",
                             $time,
                             vif.beat_id,
                             current_path,
                             vif.addr,
                             vif.rdata,
                             expected_mem[vif.addr]);

                end

                else
                begin

                    if(vif.use_axi)
                        axi_fail++;
                    else
                        bridge_fail++;

                    $display("[%0t] READ FAIL beat=%0d path=%6s addr=%0h data=%0h (expected=%0h)",
                             $time,
                             vif.beat_id,
                             current_path,
                             vif.addr,
                             vif.rdata,
                             expected_mem[vif.addr]);
                end
            end
        end
    endtask
endclass

class environment;
    generator gen;
    driver drv;
    monitor mon;
    functional_coverage fcov;
    mailbox #(cpu_transaction) mb;
    virtual cpu_if vif;
    function new(virtual cpu_if vif);
        this.vif = vif;
        mb = new();
        gen = new(mb);
        drv = new(vif, mb);
        mon = new(vif);
        fcov = new(vif);
    endfunction

    task run();
        fork
            gen.run();
            drv.run();
            mon.run();
            fcov.run();
        join_any
    endtask
endclass
module tb;
logic clk;
cpu_if vif(clk);
top_memory_system dut(vif);
environment env;
// ============================================
// CLOCK GENERATION
// ============================================
initial
begin
    clk = 0;
    forever #10 clk = ~clk;
end
// ============================================
// RESET AND SIGNAL INITIALIZATION
// ============================================
initial
begin
    vif.reset = 1;
    vif.addr  = 0;
    vif.wdata = 0;
    vif.write = 0;
    vif.read  = 0;
    vif.burst_hint = 0;
    #50;
    vif.reset = 0;
end
// ============================================
// ENVIRONMENT START
// ============================================
initial
begin
    env = new(vif);
    wait(vif.reset == 0);
    env.run();
end

// ============================================
// SIMULATION FINISH
// ============================================

initial
begin
    #5000;
    $display("");
    $display("====================================================");
    $display("               FINAL SCOREBOARD SUMMARY             ");
    $display("====================================================");
    $display("AXI Path     - Passes: %0d, Fails: %0d", env.mon.axi_pass, env.mon.axi_fail);
    $display("APB Path     - Passes: %0d, Fails: %0d", env.mon.bridge_pass, env.mon.bridge_fail);
    $display("----------------------------------------------------");
    $display("Protocol Switches: APB->AXI = %0d, AXI->APB = %0d",
             env.mon.apb_to_axi_count, env.mon.axi_to_apb_count);
    $display("====================================================");
    if (env.mon.axi_fail == 0 && env.mon.bridge_fail == 0)
        $display("STATUS: VERIFICATION PASSED");
    else
        $display("STATUS: VERIFICATION FAILED");
    $display("====================================================");
    // Print functional coverage report
    env.fcov.report();
    $finish;
end
endmodule