// ============================================================// CPU INTERFACE (UPDATED AXI VERSION)// ============================================================

interface cpu_if(input logic clk);

logic reset;

// =====================================
// COMMON
// =====================================

logic [7:0] addr;

logic write;
logic read;

logic [3:0] burst_len;
logic [1:0] qos;

logic sequential_access;

// =====================================
// AXI WRITE ADDRESS CHANNEL
// =====================================

logic awvalid;
logic awready;


// =====================================
// AXI WRITE DATA CHANNEL
// =====================================

logic [31:0] wdata;

logic wvalid;
logic wready;

logic wlast;


// =====================================
// AXI WRITE RESPONSE CHANNEL
// =====================================

logic [1:0] bresp;

logic bvalid;
logic bready;


// =====================================
// AXI READ ADDRESS CHANNEL
// =====================================

logic arvalid;
logic arready;


// =====================================
// AXI READ DATA CHANNEL
// =====================================

logic [31:0] rdata;

logic [1:0] rresp;

logic rvalid;
logic rready;

logic rlast;

endinterface

// ============================================================// ADDRESS DECODER// ============================================================// ============================================================// MULTI-SLAVE ADDRESS DECODER// ============================================================



// ============================================================// SRAM MODEL// ============================================================
module sram_model(
  input logic reset,
  input  logic clk,
  input  logic we,
  input  logic [7:0] addr,
  input  logic [31:0] wdata,
  output logic [31:0] rdata

);

logic [31:0] mem [0:255];

always_ff @(posedge clk)begin

if(we && addr < 8'h40)
begin
    mem[addr] <= wdata;
end

end
  
  always_ff @(posedge clk)
begin

    if(addr < 8'h40)
        rdata <= mem[addr];

    else
        rdata <= 32'hDEADBEEF;

end

endmodule

// ============================================================// AXI FIFO BUFFER// ============================================================

module axi_fifo(

input logic clk,
input logic reset,

input logic write_en,
input logic read_en,

input logic [7:0] addr_in,
input logic [31:0] data_in,

output logic [7:0] addr_out,
output logic [31:0] data_out,
output logic valid_out,

output logic full,
output logic empty

);

parameter DEPTH = 16;

// =====================================// FIFO STORAGE// =====================================

logic [7:0]  addr_mem [0:DEPTH-1];
logic [31:0] data_mem [0:DEPTH-1];

logic fifo_full;
  logic fifo_empty;

logic hold_valid;

integer wr_ptr;
  integer rd_ptr;
  integer count;

// =====================================// MAIN FIFO LOGIC// =====================================

always_ff @(posedge clk)begin

if(reset)
begin

    wr_ptr  <= 0;
    rd_ptr  <= 0;
    count   <= 0;

    addr_out <= 0;
    data_out <= 0;

end

else
begin

    // =========================
    // WRITE OPERATION
    // =========================

    // =========================

// WRITE ONLY// =========================

if(write_en && !read_en && !fifo_full)begin

addr_mem[wr_ptr] <= addr_in;
data_mem[wr_ptr] <= data_in;

wr_ptr <= (wr_ptr + 1) % DEPTH;

count <= count + 1;

end

// =========================// READ ONLY// =========================

else if(read_en && !write_en && !fifo_empty)begin

addr_out <= addr_mem[rd_ptr];
data_out <= data_mem[rd_ptr];

rd_ptr <= (rd_ptr + 1) % DEPTH;

count <= count - 1;

end

// =========================// SIMULTANEOUS READ/WRITE// =========================

else if(write_en && read_en &&!fifo_full && !fifo_empty)begin

// WRITE NEW ENTRY

addr_mem[wr_ptr] <= addr_in;
data_mem[wr_ptr] <= data_in;

wr_ptr <= (wr_ptr + 1) % DEPTH;

// READ OLD ENTRY

addr_out <= addr_mem[rd_ptr];
data_out <= data_mem[rd_ptr];

rd_ptr <= (rd_ptr + 1) % DEPTH;

// count unchanged

end

end

end

// =====================================// VALID HOLD LOGIC// =====================================

always_ff @(posedge clk)begin

if(reset)
    hold_valid <= 0;

else
begin

    // Hold valid for one clean cycle
    // after successful FIFO pop

    if(read_en && !fifo_empty)
        hold_valid <= 1;

    else
        hold_valid <= 0;

end

end

// =====================================// STATUS SIGNALS// =====================================

assign valid_out = hold_valid;

assign fifo_full  = (count == DEPTH);assign fifo_empty = (count == 0);

assign full  = fifo_full;assign empty = fifo_empty;

endmodule



// ============================================================// AXI-ONLY TOP SYSTEM// ============================================================
module top_axi_system(

cpu_if vif

);

logic [31:0] sram_rdata;

logic [7:0] fifo_addr;logic [31:0] fifo_data;
logic [7:0] fifo_addr_d;logic [31:0] fifo_data_d;
logic fifo_full;logic fifo_empty;logic fifo_valid;logic fifo_pop;

logic sram_we_d;
  logic read_pending;

logic [7:0] sram_addr_d;logic [31:0] sram_data_d;

logic [31:0] write_count;logic [31:0] read_count;logic [31:0] burst_count;logic [31:0] stall_count;
logic [3:0] burst_counter;logic [3:0] write_burst_counter;

logic [2:0] qos_cnt;
always_ff @(posedge vif.clk) begin
    if(vif.reset) qos_cnt <= 0;
    else qos_cnt <= qos_cnt + 1;
end

// =====================================// FIFO// WRITE BUFFER ONLY// =====================================

axi_fifo fifo(

.clk(vif.clk),
.reset(vif.reset),

.write_en(vif.wvalid && vif.wready && !fifo_full),

// ONLY WRITE POP

.read_en(fifo_pop),

.addr_in(vif.addr),
.data_in(vif.wdata),

.addr_out(fifo_addr),
.data_out(fifo_data),

.valid_out(fifo_valid),

.full(fifo_full),
.empty(fifo_empty)

);



// =====================================// FIFO OUTPUT PIPELINE// =====================================

always_ff @(posedge vif.clk)begin

if(vif.reset)
begin

    fifo_addr_d <= 0;
    fifo_data_d <= 0;

end

else if(fifo_valid)
begin

    fifo_addr_d <= fifo_addr;
    fifo_data_d <= fifo_data;

end

end



// =====================================// PERFORMANCE COUNTERS// =====================================

always_ff @(posedge vif.clk)begin

if(vif.reset)
begin

    write_count <= 0;
    read_count  <= 0;
    burst_count <= 0;
    stall_count <= 0;

end

else
begin

    if(vif.write && vif.wready)
        write_count <= write_count + 1;

    if(vif.read && vif.rvalid)
        read_count <= read_count + 1;

    if(vif.write || vif.read)
        burst_count <= burst_count + 1;

    if((vif.awvalid && !vif.awready) ||
       (vif.wvalid  && !vif.wready))
        stall_count <= stall_count + 1;

end

end

// =====================================// FIFO POP CONTROL// =====================================

always_ff @(posedge vif.clk) begin

    if(vif.reset)
        fifo_pop <= 0;

    else
    begin

        // pop only after write completed

        if(vif.wvalid && vif.wready && !fifo_empty)
   
            fifo_pop <= 1;

        else
            fifo_pop <= 0;

    end

end

// =====================================// SRAM WRITE PIPELINE// =====================================

always_ff @(posedge vif.clk)begin

if(vif.reset)
begin

    sram_we_d   <= 0;

    sram_addr_d <= 0;
    sram_data_d <= 0;

end

else
begin

    // default

    sram_we_d <= 0;


    // latch FIFO output
if(fifo_valid)
begin

    sram_addr_d <= fifo_addr;
    sram_data_d <= fifo_data;

end


// WRITE ENABLE AFTER DATA LATCHED

if(fifo_valid)
begin

    if(sram_addr_d < 8'h40)
        sram_we_d <= 1;

end
  

end

end

// =====================================// SRAM// =====================================

// =====================================// SRAM// =====================================

sram_model sram(

.reset(vif.reset),

.clk(vif.clk),

.we(sram_we_d),

.addr(
    vif.read ? vif.addr :
    sram_addr_d
),

.wdata(sram_data_d),

.rdata(sram_rdata)

);

// =====================================// READ MUX// =====================================
  always_ff @(posedge vif.clk)
begin

    vif.rdata <= sram_rdata;

end
// =====================================// AXI WRITE HANDSHAKE// =====================================

// =====================================
// AXI WRITE HANDSHAKE
// =====================================

always_ff @(posedge vif.clk)
begin

if(vif.reset)
begin

    vif.awvalid <= 0;
    vif.wvalid  <= 0;
    vif.bvalid  <= 0;

    vif.awready <= 0;
    vif.wready  <= 0;

    vif.bresp   <= 2'b00;

    write_burst_counter <= 0;

end

else
begin

    // =========================
    // VALID GENERATION
    // =========================

    if(vif.write)
    begin

        vif.awvalid <= 1;
        vif.wvalid  <= 1;

    end


    // =========================
    // QoS PRIORITY READY LOGIC
    // =========================

    case(vif.qos)

        // HIGH PRIORITY

        2'b11:
        begin

            vif.awready <= 1;
            vif.wready  <= 1;

        end


        // MEDIUM PRIORITY

        2'b10:
        begin

            vif.awready <=
                (qos_cnt != 3'b000);

            vif.wready  <=
                (qos_cnt != 3'b000);

        end


        // LOW PRIORITY

        2'b01:
        begin

            vif.awready <=
                (qos_cnt[1:0] != 2'b00);

            vif.wready  <=
                (qos_cnt[1:0] != 2'b00);

        end


        // BACKGROUND TRAFFIC

        default:
        begin

            vif.awready <=
                (qos_cnt[0] != 1'b0);

            vif.wready  <=
                (qos_cnt[0] != 1'b0);

        end

    endcase


    // =========================
    // HANDSHAKE COMPLETE
    // =========================

    if(vif.awvalid && vif.awready)
        vif.awvalid <= 0;

    if(vif.wvalid && vif.wready)
        vif.wvalid <= 0;


    // =========================
    // WRITE RESPONSE
    // =========================

    if(fifo_valid)
    begin

        vif.bvalid <= 1;
        vif.bresp  <= 2'b00;

    end

    if(vif.bvalid && vif.bready)
        vif.bvalid <= 0;


    // =========================
    // BURST TRACKING
    // =========================

    if(vif.wvalid && vif.wready)
    begin

        write_burst_counter
            <= write_burst_counter + 1;

        if(write_burst_counter
            == vif.burst_len-1)

            write_burst_counter <= 0;

    end

end

end

// =====================================
// AXI READ HANDSHAKE
// =====================================

always_ff @(posedge vif.clk)
begin

if(vif.reset)
begin

    vif.arvalid <= 0;
    vif.rvalid  <= 0;

    vif.arready <= 0;

    vif.rlast   <= 0;

    vif.rresp   <= 2'b00;

    burst_counter <= 0;

    read_pending <= 0;

end

else
begin

    // =========================
    // ADDRESS VALID
    // =========================

    if(vif.read)
        vif.arvalid <= 1;


    // =========================
    // QoS READY CONTROL
    // =========================

    case(vif.qos)

        // HIGH PRIORITY

        2'b11:
        begin

            vif.arready <= 1;

        end


        // MEDIUM PRIORITY

        2'b10:
        begin

            vif.arready <=
                (qos_cnt != 3'b000);

        end


        // LOW PRIORITY

        2'b01:
        begin

            vif.arready <=
                (qos_cnt[1:0] != 2'b00);

        end


        // BACKGROUND TRAFFIC

        default:
        begin

            vif.arready <=
                (qos_cnt[0] != 1'b0);

        end

    endcase


    // =========================
    // ADDRESS HANDSHAKE
    // =========================

    if(vif.arvalid && vif.arready)
    begin

        vif.arvalid <= 0;

    end


    // =========================
    // READ RESPONSE PIPELINE
    // =========================

    if(vif.read &&
       !vif.rvalid &&
       !read_pending)
    begin

        read_pending <= 1;

    end

    else if(read_pending)
    begin

        vif.rvalid <= 1;
        vif.rresp  <= 2'b00;

        read_pending <= 0;

    end


    // =========================
    // READ COMPLETE
    // =========================

    if(vif.rvalid && vif.rready)
    begin

        vif.rvalid <= 0;

        burst_counter
            <= burst_counter + 1;

        if(burst_counter
            == vif.burst_len-1)

            burst_counter <= 0;

    end


    // =========================
    // LAST BURST
    // =========================

    if(burst_counter
        == vif.burst_len-1)

        vif.rlast <= 1;

    else

        vif.rlast <= 0;

end

end

// =====================================

// ASSERTIONS// =====================================

property awvalid_until_ready;

	@(posedge vif.clk)
		vif.awvalid |->(vif.awvalid until vif.awready);

endproperty

assert property(awvalid_until_ready);

property wlast_on_final_burst;

@(posedge vif.clk)
vif.wlast |-> (vif.burst_len >= 1);

endproperty

assert property(wlast_on_final_burst);
endmodule

