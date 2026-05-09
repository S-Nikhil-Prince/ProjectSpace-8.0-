// ============================================================
// CPU INTERFACE
// ============================================================

interface cpu_if(input logic clk);

    logic reset;

    // Common signals
    logic [7:0] addr;
    logic [31:0] wdata;
    logic [31:0] rdata;
    logic [7:0] continuous_count;

    logic write;
    logic read;

    logic use_axi;
    logic use_apb;

    // ==========================
    // AXI-Lite Signals
    // ==========================

    logic awvalid;
    logic awready;

    logic wvalid;
    logic wready;

    logic bvalid;
    logic bready;

    logic arvalid;
    logic arready;

    logic rvalid;
    logic rready;

    // ==========================
    // APB Signals
    // ==========================

    logic psel;
    logic penable;
    logic pwrite;
    logic pslverr;
    logic pready;
  
  logic burst_axi;
logic burst_bridge;
  
  logic sequential_access;
logic random_access;
  
  logic [7:0] burst_id;
logic [7:0] beat_id;
logic [7:0] total_beats;

endinterface


module traffic_classifier(

    input  logic clk,
    input  logic reset,

    input  logic write,
    input  logic read,

    input  logic [7:0] addr,

    output logic use_axi,
    output logic use_apb,

    output logic sequential_access,
    output logic random_access,

    output logic [7:0] continuous_count

);

logic [7:0] prev_addr;

always_ff @(posedge clk or posedge reset)
begin

    if(reset)
    begin

        prev_addr         <= 0;

        continuous_count  <= 0;

        sequential_access <= 0;
        random_access     <= 0;

        use_axi           <= 0;
        use_apb           <= 1;

    end

    else
    begin

        if(write || read)
        begin

            continuous_count <= continuous_count + 1;

            // =========================
            // Sequential Access
            // =========================
            if(
                (addr == prev_addr + 1) ||
                (addr == prev_addr)
            )
            begin

                sequential_access <= 1;
                random_access     <= 0;

                use_axi <= 1;
                use_apb <= 0;

            end

            // =========================
            // Random Access
            // =========================
            else
            begin

                sequential_access <= 0;
                random_access     <= 1;

                use_axi <= 0;
                use_apb <= 1;

            end

            prev_addr <= addr;

        end

        else
        begin

            continuous_count <= 0;

        end

    end

end

endmodule


// ============================================================
// APB FIFO
// ============================================================

module apb_fifo(

    input logic clk,
    input logic reset,
    input logic write_en,
    input logic read_en,

    input logic [31:0] data_in,
    output logic [31:0] data_out,

    output logic full,
    output logic empty

);

logic [31:0] fifo [0:7];

logic [2:0] w_ptr;
logic [2:0] r_ptr;

logic [3:0] count;

assign full  = (count == 8);
assign empty = (count == 0);

always_ff @(posedge clk)
begin
    if (reset) begin
        w_ptr    <= '0;
        r_ptr    <= '0;
        count    <= '0;
        data_out <= '0;
    end
    else begin

        if(write_en && !full)
        begin
            fifo[w_ptr] <= data_in;
            w_ptr <= w_ptr + 1;
            count <= count + 1;
        end

        if(read_en && !empty)
        begin
            data_out <= fifo[r_ptr];
            r_ptr <= r_ptr + 1;
            count <= count - 1;
        end
    end

end

endmodule





// ============================================================
// SRAM MODEL
// ============================================================

module sram_model(

    input logic clk,
    input logic reset,
    input logic we,
    input logic [7:0] addr,
    input logic [31:0] wdata,
    output logic [31:0] rdata

);

logic [31:0] mem [0:255];

integer i;
integer cycle_count;

always_ff @(posedge clk)
begin
    if(we && addr < 8'h40)
    begin
        mem[addr] <= wdata;

    end
end

assign rdata = mem[addr];

always_ff @(posedge clk)
begin
    if (reset) cycle_count <= 0;
    else       cycle_count <= cycle_count + 1;
end

always_ff @(posedge clk)
begin
`ifndef SYNTHESIS

    if(cycle_count % 20 == 0)
    begin

        $display("\n==================================");
        $display(" REAL-TIME RAM MEMORY CONTENT ");
        $display("==================================");

        for(i=0;i<16;i++)
        begin
            $display("Addr[%0h] = %h",
                      i,
                      mem[i]);
        end

        $display("==================================");

    end

`endif
end

endmodule





// ============================================================
// TOP SYSTEM
// ============================================================

module top_memory_system(

    cpu_if vif

);

    logic [31:0] ram_rdata;

    logic [31:0] fifo_data;
    logic fifo_full;
    logic fifo_empty;
  
    traffic_classifier tc(
        .clk(vif.clk),
        .reset(vif.reset),
        .write(vif.write),
        .read(vif.read),
        .addr(vif.addr),
        .use_axi(vif.use_axi),
        .use_apb(vif.use_apb),
        .continuous_count(vif.continuous_count),
        .sequential_access(vif.sequential_access),
        .random_access(vif.random_access)
    );

    sram_model ram(
        .clk(vif.clk),
        .reset(vif.reset),
        .we(vif.write),
        .addr(vif.addr),
        .wdata(vif.wdata),
        .rdata(ram_rdata)
    );

apb_fifo fifo(

    .clk(vif.clk),
    .reset(vif.reset),

    .write_en(vif.write & vif.use_axi),
    .read_en(vif.read & vif.use_apb),

    .data_in(vif.wdata),
    .data_out(fifo_data),

    .full(fifo_full),
    .empty(fifo_empty)

);

always_comb
begin

    vif.rdata <= ram_rdata;

end

always_ff @(posedge vif.clk)
begin

    if (vif.reset)
    begin
        vif.awvalid <= 0;
        vif.awready <= 0;
        vif.wvalid  <= 0;
        vif.wready  <= 0;
        vif.bvalid  <= 0;
    end
    else if(vif.use_axi && vif.write)
    begin

        vif.awvalid <= 1;
        vif.awready <= 1;

        vif.wvalid  <= 1;
        vif.wready  <= 1;

        vif.bvalid <= 1;

    end
    else
    begin

        vif.awvalid <= 0;
        vif.wvalid  <= 0;

        vif.bvalid  <= 0;
        vif.awready <= 0;
        vif.wready  <= 0;

    end

end

always_ff @(posedge vif.clk)
begin

    if (vif.reset)
    begin
        vif.arvalid <= 0;
        vif.arready <= 0;
        vif.rvalid  <= 0;
    end
    else if(vif.use_axi && vif.read)
    begin

        vif.arvalid <= 1;
        vif.arready <= 1;

        vif.rvalid <= 1;

    end
    else
    begin

        vif.arvalid <= 0;
        vif.arready <= 0;

        vif.rvalid <= 0;

    end

end

always_ff @(posedge vif.clk)
begin

    if (vif.reset)
    begin
        vif.psel    <= 0;
        vif.penable <= 0;
        vif.pwrite  <= 0;
        vif.pready  <= 0;
    end
    else if(vif.use_apb)
    begin

        vif.psel <= 1;
        vif.penable <= 0;

        vif.pwrite <= vif.write;

        vif.penable <= 1;

        vif.pready <= 1;

    end
    else
    begin

        vif.psel <= 0;
        vif.penable <= 0;
        vif.pready <= 0;
        vif.pwrite <= 0;

    end

end

endmodule