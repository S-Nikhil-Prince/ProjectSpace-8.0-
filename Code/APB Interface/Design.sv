// ============================================================
// CPU INTERFACE (APB-ONLY VERSION)
// ============================================================

interface cpu_if(input logic clk);

    logic reset;

    // Common signals
    logic [7:0] addr;
    logic [31:0] wdata;
    logic [31:0] rdata;

    logic write;
    logic read;

    // ==========================
    // APB Signals
    // ==========================

    logic psel;
    logic penable;
    logic pwrite;
    logic pready;

    logic [7:0] burst_id;
    logic [7:0] beat_id;
    logic [7:0] total_beats;

endinterface

// ============================================================
// APB FIFO
// ============================================================

module apb_fifo(

    input logic clk,
    input logic reset,
    input logic write_en,
    input logic read_en,

    input logic [31:0] data_in,
    input logic [7:0] addr_in,
    output logic [31:0] data_out,
    output logic [7:0] addr_out,

    output logic full,
    output logic empty

);

logic [31:0] fifo_data [0:15];
logic [7:0]  fifo_addr [0:15];

logic [3:0] w_ptr;
logic [3:0] r_ptr;

logic [4:0] count;

assign full  = (count == 16);
assign empty = (count == 0);

always_ff @(posedge clk)
begin
    if (reset) begin
        w_ptr    <= '0;
        r_ptr    <= '0;
        count    <= '0;
        data_out <= '0;
        addr_out <= '0;
    end
    else begin

        if(write_en && !full)
        begin
            fifo_data[w_ptr] <= data_in;
            fifo_addr[w_ptr] <= addr_in;
            w_ptr <= w_ptr + 1;
            count <= count + 1;
        end

        if(read_en && !empty)
        begin
            data_out <= fifo_data[r_ptr];
            addr_out <= fifo_addr[r_ptr];
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

module top_apb_system(

    cpu_if vif

);

    logic [31:0] ram_rdata;

    logic [31:0] fifo_data;
    logic [7:0]  fifo_addr;
    logic fifo_full;
    logic fifo_empty;
    logic fifo_pop;
    
    // Pop from FIFO when it has data
    assign fifo_pop = !fifo_empty;
  
    apb_fifo fifo(
        .clk(vif.clk),
        .reset(vif.reset),
        .write_en(vif.write),
        .read_en(fifo_pop),
        .data_in(vif.wdata),
        .addr_in(vif.addr),
        .data_out(fifo_data),
        .addr_out(fifo_addr),
        .full(fifo_full),
        .empty(fifo_empty)
    );

    // Write to SRAM when FIFO pops
    logic sram_we;
    always_ff @(posedge vif.clk) begin
        if(vif.reset)
            sram_we <= 0;
        else
            sram_we <= fifo_pop; // Write takes 1 cycle after pop
    end

    sram_model ram(
        .clk(vif.clk),
        .reset(vif.reset),
        .we(sram_we),
        .addr(vif.read ? vif.addr : fifo_addr),
        .wdata(fifo_data),
        .rdata(ram_rdata)
    );

always_comb
begin
    vif.rdata = ram_rdata;
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
    else if(vif.write || vif.read)
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
