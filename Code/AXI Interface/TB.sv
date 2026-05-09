// ============================================================// TRANSACTION CLASS// ============================================================

class cpu_transaction;

// =====================================
// RANDOM VARIABLES
// =====================================

rand bit [7:0]  addr;
rand bit [31:0] wdata;

rand bit write;
rand bit read;

rand bit [3:0] burst_len;
rand bit [1:0] qos;

// 1 = Sequential AXI traffic
// 0 = Random AXI traffic

rand bit sequential_access;


// =====================================
// ADDRESS RANGE
// =====================================

constraint addr_range {

    addr inside {[0:127]};

}


// =====================================
// BURST RANGE
// =====================================

constraint burst_range {

    burst_len inside {[1:8]};

}


// =====================================
// QoS RANGE
// =====================================

constraint qos_range {

    qos inside {[0:3]};

}


// =====================================
// READ / WRITE DISTRIBUTION
// =====================================

constraint operation_valid {

    write dist {
        1 := 60,
        0 := 40
    };

    // Only one operation at a time

    read == !write;

}


// =====================================
// AXI TRAFFIC TYPE
// =====================================

constraint traffic_type {

    sequential_access dist {

        // 70% Sequential AXI traffic

        1 := 70,

        // 30% Random AXI traffic

        0 := 30

    };

}

endclass

// ============================================================// GENERATOR// ============================================================
class generator;

cpu_transaction tr;

mailbox #(cpu_transaction) gen2drv;

function new(mailbox #(cpu_transaction) mb);
    gen2drv = mb;
endfunction


task run();

    repeat(100)
    begin

        tr = new();

        assert(tr.randomize());

        gen2drv.put(tr);

    end

endtask

endclass



// ============================================================// DRIVER (AXI ONLY — No Switching)// ============================================================
class driver;

virtual cpu_if vif;

mailbox #(cpu_transaction) gen2drv;

// Store written addresses
bit [7:0] write_addr_queue[$];

function new(
    virtual cpu_if vif,
    mailbox #(cpu_transaction) mb
);
    this.vif = vif;
    gen2drv = mb;
endfunction


task run();

    cpu_transaction tr;

    integer i;

    // Declare variables at top
    bit [7:0] current_addr;
    integer index;
  integer write_phase_count = 0;

    forever
    begin
       bit [7:0] burst_used_addr[$];

       gen2drv.get(tr);

// =====================================
// FORCE INITIAL WRITE PHASE
// =====================================

if(write_addr_queue.size() < 10)
begin

    tr.write = 1;
    tr.read  = 0;

end

else
begin

    tr.read  = $urandom_range(0,1);

    if(tr.read)
        tr.write = 0;
    else
        tr.write = 1;

end

vif.write <= tr.write;
vif.read  <= tr.read;

        vif.burst_len <= tr.burst_len;
        vif.qos       <= tr.qos;
      vif.sequential_access <= tr.sequential_access;


        for(i = 0; i < tr.burst_len; i++)
        begin

            @(posedge vif.clk);

            // WRITE OPERATION

           // =====================================

// WRITE OPERATION// =====================================

if(tr.write)begin

// =====================================

// AXI TRAFFIC PATTERN// =====================================

if(tr.sequential_access)

// Sequential AXI traffic

current_addr =
  (tr.addr + i) & 8'h7F;

else
begin

   bit duplicate_addr;

duplicate_addr = 1;

while(duplicate_addr)
begin

    duplicate_addr = 0;

    current_addr =
        $urandom_range(0,127);

    // check previous global writes

    foreach(write_addr_queue[j])
    begin

        if(write_addr_queue[j]
           == current_addr)
        begin

            duplicate_addr = 1;
        end

    end

    // check current burst addresses

    foreach(burst_used_addr[k])
    begin

        if(burst_used_addr[k]
           == current_addr)
        begin

            duplicate_addr = 1;
        end

    end

end

burst_used_addr.push_back(current_addr);

end
  
  

// Drive address/data

vif.addr  <= current_addr;
vif.wdata <= $urandom();

// WLAST

if(i == tr.burst_len-1)
    vif.wlast <= 1;
else
    vif.wlast <= 0;


// WAIT FOR HANDSHAKE

do begin
    @(posedge vif.clk);
end while(!(vif.wready && vif.awready));



@(posedge vif.clk);

// Store written address

if(current_addr < 8'h40)
begin
    write_addr_queue.push_back(current_addr);
end
  write_phase_count = write_phase_count + 1;
end

            // READ OPERATION

            // =====================================

// READ OPERATION// =====================================

else if(tr.read) begin

    // Read only previously written SRAM addresses

    if(write_addr_queue.size() > 0)
    begin

        index =
$urandom_range(
    0,
    write_addr_queue.size()-1
);

vif.addr <= write_addr_queue[index];

// remove after read
write_addr_queue.delete(index);

    end

    else
    begin

        // fallback SRAM address

        vif.addr <= $urandom_range(0,63);

    end

    vif.read <= 1;

   

    // ADDRESS HANDSHAKE

    do begin
        @(posedge vif.clk);
    end while(!vif.arready);

 

    // WAIT FOR DATA

    do begin
        @(posedge vif.clk);
    end while(!vif.rvalid);
    @(posedge vif.clk);
	@(posedge vif.clk);
  @(posedge vif.clk);
	@(posedge vif.clk);
    vif.read <= 0;

end

        end   // END FOR LOOP

        @(posedge vif.clk);

        vif.write   <= 0;
        vif.read    <= 0;
        vif.wlast   <= 0;

    end   // END FOREVER

endtask

endclass

// ============================================================// MONITOR// ============================================================
class monitor;


virtual cpu_if vif;
  logic [31:0] expected_mem [0:255];

function new(virtual cpu_if vif);
    this.vif = vif;
endfunction

integer burst_id = 0;task run();

integer burst_counter;
integer burst_len_local;
  logic [7:0]  sampled_addr;
logic [31:0] sampled_data;

integer burst_id = 0;


forever
begin

    @(posedge vif.clk);

    // =====================================
    // START OF NEW BURST
    // =====================================

    if((vif.awvalid && vif.awready) ||
       (vif.arvalid && vif.arready))
    begin

        burst_counter   = 0;
        burst_len_local = vif.burst_len;

$display("");

$display("====================================================");
$display("AXI BURST %0d", burst_id);
$display("Burst Length = %0d", burst_len_local);
$display("====================================================");


while(burst_counter < burst_len_local)
begin

    @(posedge vif.clk);


    // =============================
    // WRITE HANDSHAKE
    // =============================

    if(vif.wvalid &&
   vif.wready)
    begin

        expected_mem[vif.addr] = vif.wdata;

        $display("[%0t] WRITE beat=%0d path=AXI addr=%0h data=%0h",
                  $time,
                  burst_counter,
                  vif.addr,
                  vif.wdata);

        burst_counter++;

    end


    // =============================
    // READ HANDSHAKE
    // =============================

    else if(vif.rvalid &&
        vif.rready)
    begin

        @(posedge vif.clk);

        sampled_addr = vif.addr;
        sampled_data = vif.rdata;

        if(sampled_data ==
           expected_mem[sampled_addr])
        begin

            $display("[%0t] READ  beat=%0d path=AXI addr=%0h data=%0h (expected=%0h)",
                      $time,
                      burst_counter,
                      sampled_addr,
                      sampled_data,
                      expected_mem[sampled_addr]);

        end

        burst_counter++;

    end

end   // while loop


        burst_id++;

    end   // if burst start

end   // forever loop

endtask

endclass

// ============================================================// ENVIRONMENT// ============================================================
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

// ============================================================// TESTBENCH// ============================================================
module tb;

logic clk;

cpu_if vif(clk);

top_axi_system dut(vif);

environment env;

// CLOCK

initial begin 
  clk = 0;
  forever 
    #10 clk = ~clk;
end
 
// RESET

initial begin

vif.reset = 1;

vif.addr  = 0;
vif.wdata = 0;
vif.write = 0;
vif.read  = 0;

vif.burst_len = 1;
vif.qos = 0;

vif.bready = 1;
vif.rready = 1;

#50;

vif.reset = 0;

end

// ENV

initial begin

env = new(vif);

wait(vif.reset == 0);

env.run();

end

// STOP

initial begin

#5000;
$finish;

end

endmodule