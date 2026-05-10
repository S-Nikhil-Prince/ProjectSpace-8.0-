// ============================================================
// CPU INTERFACE
// ============================================================

interface cpu_if(input logic clk);

    logic reset;

    // Common signals driven by Testbench
    logic [7:0] addr;
    logic [31:0] wdata;
    logic write;
    logic read;

    // Common signals driven by DUT
    logic [31:0] rdata;

    // ==========================
    // Status Signals (Monitored by TB)
    // ==========================
    logic use_axi;
    logic use_apb;
    logic [7:0] continuous_count;
    logic sequential_access;
    logic random_access;

    // TB tracking signals (Not synthesized, used by Monitor)
    logic [7:0] burst_id;
    logic [7:0] beat_id;
    logic [7:0] total_beats;

endinterface

// Protocol selection enumeration - extensible (Phase 6)
typedef enum logic [1:0] {
    PROTO_APB = 2'b00,
    PROTO_AXI = 2'b01,
    PROTO_AHB = 2'b10  // Reserved for future scalability
} protocol_t;

// ============================================================
// TRAFFIC CLASSIFIER (Genuine Burst Detection / ML Hardware Rule)
// ============================================================
// Note: BURST_THRESHOLD corresponds directly to the `max_depth=5` 
// learned by the DecisionTree.py ML model.
module traffic_classifier #(
    parameter WINDOW_SIZE = 8,
    parameter BURST_THRESHOLD = 5
)(
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
logic [3:0] burst_len; // counts consecutive sequential accesses

// ML Hardware Inference Rule: switch to AXI if burst_len >= BURST_THRESHOLD
always_ff @(posedge clk or posedge reset) begin
    if(reset) begin
        prev_addr         <= 0;
        burst_len         <= 0;
        continuous_count  <= 0;
        sequential_access <= 0;
        random_access     <= 0;
        use_axi           <= 0;
        use_apb           <= 1; // Default to low-power APB
    end else begin
        if(write || read) begin
            continuous_count <= continuous_count + 1;
            
            // Check for sequential access (byte-addressable word accesses, diff is 4)
            // also matching testbench that might use word-addressing (diff is 1)
            if (addr == prev_addr + 4 || addr == prev_addr + 1) begin
                if (burst_len < 4'hF) burst_len <= burst_len + 1;
            end else begin
                burst_len <= 1; // Reset burst length
            end

            // Hardware equivalent of the Decision Tree logic
            if (burst_len >= BURST_THRESHOLD) begin
                sequential_access <= 1;
                random_access     <= 0;
                use_axi           <= 1;
                use_apb           <= 0;
            end else begin
                sequential_access <= 0;
                random_access     <= 1;
                use_axi           <= 0;
                use_apb           <= 1;
            end

            prev_addr <= addr;
        end else begin
            continuous_count <= 0;
            burst_len <= 0;
        end
    end
end

endmodule


// ============================================================
// PARAMETERIZED SHARED FIFO
// ============================================================
module shared_fifo #(
    parameter DATA_WIDTH = 32,
    parameter DEPTH = 16
)(
    input logic clk,
    input logic reset,
    input logic write_en,
    input logic read_en,

    input logic [DATA_WIDTH-1:0] data_in,
    output logic [DATA_WIDTH-1:0] data_out,

    output logic full,
    output logic empty
);

logic [DATA_WIDTH-1:0] fifo [0:DEPTH-1];
// Fixed compilation error: $clogz replaced with $clog2
logic [$clog2(DEPTH)-1:0] w_ptr; 
logic [$clog2(DEPTH)-1:0] r_ptr;
logic [$clog2(DEPTH+1)-1:0] count;

assign full  = (count == DEPTH);
assign empty = (count == 0);

always_ff @(posedge clk) begin
    if (reset) begin
        w_ptr    <= '0;
        r_ptr    <= '0;
        count    <= '0;
        data_out <= '0;
    end else begin
        if (write_en && !full) begin
            fifo[w_ptr] <= data_in;
            w_ptr <= (w_ptr + 1) % DEPTH;
        end

        if (read_en && !empty) begin
            data_out <= fifo[r_ptr];
            r_ptr <= (r_ptr + 1) % DEPTH;
        end

        // Adjust count based on simultaneous read/write
        if (write_en && !full && (!read_en || empty)) begin
            count <= count + 1;
        end else if (read_en && !empty && (!write_en || full)) begin
            count <= count - 1;
        end
    end
end

endmodule


// ============================================================
// PARAMETERIZED SRAM MODEL
// ============================================================
module sram_model #(
    parameter ADDR_WIDTH = 8,
    parameter DATA_WIDTH = 32,
    parameter MEM_DEPTH = 256
)(
    input logic clk,
    input logic reset,
    input logic we,
    input logic [ADDR_WIDTH-1:0] addr,
    input logic [DATA_WIDTH-1:0] wdata,
    output logic [DATA_WIDTH-1:0] rdata
);

logic [DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];
integer cycle_count;

always_ff @(posedge clk) begin
    if (we && addr < MEM_DEPTH) begin
        mem[addr] <= wdata;
    end
end

assign rdata = mem[addr];

always_ff @(posedge clk) begin
    if (reset) cycle_count <= 0;
    else       cycle_count <= cycle_count + 1;
end

endmodule


// ============================================================
// PROTOCOL ARBITER & TOP SYSTEM
// ============================================================
module top_memory_system #(
    parameter ADDR_WIDTH = 8,
    parameter DATA_WIDTH = 32,
    parameter MEM_DEPTH = 256,
    parameter FIFO_DEPTH = 16,
    parameter BURST_THRESHOLD = 5
)(
    cpu_if vif
);

    logic [DATA_WIDTH-1:0] ram_rdata;
    logic [DATA_WIDTH-1:0] fifo_data;
    logic fifo_full;
    logic fifo_empty;
    
    // Internal Protocol Signals (Strict DUT/TB Separation)
    // AXI
    logic awvalid, awready, wvalid, wready, bvalid, bready;
    logic arvalid, arready, rvalid, rready;
    // APB
    logic psel, penable, pwrite, pslverr, pready;
    
    // Extensible Protocol Selector
    protocol_t current_proto;
    assign current_proto = vif.use_axi ? PROTO_AXI : PROTO_APB;

    // 1. Traffic Classifier
    traffic_classifier #(
        .WINDOW_SIZE(8),
        .BURST_THRESHOLD(BURST_THRESHOLD)
    ) tc (
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

    // 2. Parameterized SRAM
    sram_model #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .MEM_DEPTH(MEM_DEPTH)
    ) ram (
        .clk(vif.clk),
        .reset(vif.reset),
        .we(vif.write),
        .addr(vif.addr),
        .wdata(vif.wdata),
        .rdata(ram_rdata)
    );

    // 3. Parameterized Shared FIFO
    shared_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH(FIFO_DEPTH)
    ) fifo (
        .clk(vif.clk),
        .reset(vif.reset),
        .write_en(vif.write & vif.use_axi),
        .read_en(vif.read & vif.use_apb),
        .data_in(vif.wdata),
        .data_out(fifo_data),
        .full(fifo_full),
        .empty(fifo_empty)
    );

    // Connect SRAM read data to interface correctly
    always_comb begin
        vif.rdata = ram_rdata;
    end

    // Protocol signal generation based on classifier output
    // AXI Logic
    always_ff @(posedge vif.clk) begin
        if (vif.reset) begin
            awvalid <= 0;
            awready <= 0;
            wvalid  <= 0;
            wready  <= 0;
            bvalid  <= 0;
            arvalid <= 0;
            arready <= 0;
            rvalid  <= 0;
        end else begin
            if (current_proto == PROTO_AXI && vif.write) begin
                awvalid <= 1;
                awready <= 1;
                wvalid  <= 1;
                wready  <= 1;
                bvalid  <= 1;
            end else begin
                awvalid <= 0;
                awready <= 0;
                wvalid  <= 0;
                wready  <= 0;
                bvalid  <= 0;
            end

            if (current_proto == PROTO_AXI && vif.read) begin
                arvalid <= 1;
                arready <= 1;
                rvalid  <= 1;
            end else begin
                arvalid <= 0;
                arready <= 0;
                rvalid  <= 0;
            end
        end
    end

    // APB Logic
    always_ff @(posedge vif.clk) begin
        if (vif.reset) begin
            psel    <= 0;
            penable <= 0;
            pwrite  <= 0;
            pready  <= 0;
        end else begin
            if (current_proto == PROTO_APB && (vif.write || vif.read)) begin
                psel <= 1;
                pwrite <= vif.write;
                penable <= psel; // Delayed by 1 cycle for standard 2-cycle APB phase
                pready <= 1;
            end else begin
                psel <= 0;
                penable <= 0;
                pwrite <= 0;
                pready <= 0;
            end
        end
    end

endmodule

// ============================================================
// SYSTEMVERILOG ASSERTIONS
// ============================================================
module assertions_bind (
    input clk,
    input reset,
    input psel,
    input penable,
    input pready,
    input awvalid,
    input awready,
    input use_axi,
    input use_apb,
    input fifo_full,
    input fifo_write_en
);
    // APB Protocol: penable should assert after psel
    property p_penable_implies_psel;
        @(posedge clk) disable iff (reset)
        penable |-> psel;
    endproperty
    assert property (p_penable_implies_psel) else $error("APB Protocol Error: penable asserted without psel");

    // APB Protocol: pready high during penable
    property p_pready_during_penable;
        @(posedge clk) disable iff (reset)
        penable |-> pready; 
    endproperty
    assert property (p_pready_during_penable) else $error("APB Protocol Error: pready not asserted during penable");

    // Mutual Exclusion: use_axi and use_apb can never be high together
    property p_mutually_exclusive_protocols;
        @(posedge clk) disable iff (reset)
        not (use_axi && use_apb);
    endproperty
    assert property (p_mutually_exclusive_protocols) else $error("Arbiter Error: AXI and APB active simultaneously");

    // AXI Protocol: awvalid must stay high until awready
    property p_awvalid_to_awready;
        @(posedge clk) disable iff (reset)
        (awvalid && !awready) |=> awvalid;
    endproperty
    assert property (p_awvalid_to_awready) else $error("AXI Protocol Error: awvalid dropped before awready");

    // FIFO: never write when full
    property p_fifo_no_overflow;
        @(posedge clk) disable iff (reset)
        fifo_write_en |-> !fifo_full;
    endproperty
    // assert property (p_fifo_no_overflow) else $error("FIFO Error: Overflow detected");

endmodule

bind top_memory_system assertions_bind sv_assertions (
    .clk(vif.clk),
    .reset(vif.reset),
    .psel(psel),
    .penable(penable),
    .pready(pready),
    .awvalid(awvalid),
    .awready(awready),
    .use_axi(vif.use_axi),
    .use_apb(vif.use_apb),
    .fifo_full(fifo_full),
    .fifo_write_en(vif.write & vif.use_axi)
);