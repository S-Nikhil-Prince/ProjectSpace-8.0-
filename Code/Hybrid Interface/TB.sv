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

                    tr.addr = $urandom_range(0,191);
                    tr.sequential = 0;

                end

                tr.write = 1;
                tr.read  = 0;

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
            // BURST-LEVEL PROTOCOL LOCKING
            // ====================================

            if(tr.sequential)
            begin
                vif.burst_axi    <= 1;
                vif.burst_bridge <= 0;
            end
            else
            begin
                vif.burst_axi    <= 0;
                vif.burst_bridge <= 1;
            end

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


class monitor;

    virtual cpu_if vif;

    bit [31:0] expected_mem [0:255];

    integer axi_pass;
    integer axi_fail;

    integer bridge_pass;
    integer bridge_fail;

    string current_path;

    integer current_burst;

    function new(virtual cpu_if vif);

        this.vif = vif;

        current_burst = -1;

    endfunction


    task run();

        forever
        begin

            @(posedge vif.clk);

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

                if(vif.burst_axi)
                    $display("Addr style =    SEQUENTIAL (AXI path)");
                else
                    $display("Addr style = RANDOM (BRIDGE/APB path)");

                $display("====================================================");

            end

            // ====================================
            // WRITE MONITORING
            // ====================================

            if(vif.write)
            begin

                if(vif.burst_axi)
                    current_path = "AXI";
                else
                    current_path = "BRIDGE";

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

                if(vif.burst_axi)
                    current_path = "AXI";
                else
                    current_path = "BRIDGE";

                if(vif.rdata == expected_mem[vif.addr])
                begin

                    if(vif.burst_axi)
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

                    if(vif.burst_axi)
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
    mailbox #(cpu_transaction) mb;
    virtual cpu_if vif;
    function new(virtual cpu_if vif);
        this.vif = vif;
        mb = new();
        gen = new(mb);
        drv = new(vif, mb);
        mon = new(vif);
    endfunction

    task run();
        fork
            gen.run();
            drv.run();
            mon.run();
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
    vif.bready = 0;
    vif.rready = 0;
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
    $finish;
end
endmodule