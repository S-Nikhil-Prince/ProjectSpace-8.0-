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
// ADDRESS DECODER
// ============================================================

module address_decoder(

    input logic [7:0] addr,

    output logic sel_ram,
    output logic sel_uart,
    output logic sel_gpio,
    output logic sel_timer,
    output logic sel_i2c

);

always_comb
begin

    sel_ram   = 0;
    sel_uart  = 0;
    sel_gpio  = 0;
    sel_timer = 0;
    sel_i2c   = 0;

    if(addr < 8'h40)
        sel_ram = 1;

    else if(addr < 8'h60)
        sel_uart = 1;

    else if(addr < 8'h80)
        sel_gpio = 1;

    else if(addr < 8'hA0)
        sel_timer = 1;

    else if(addr < 8'hC0)
        sel_i2c = 1;

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
// UART
// ============================================================

module uart_apb(

    input logic clk,
    input logic write,
    input logic read,
    input logic [7:0] addr,
    input logic [31:0] wdata,
    output logic [31:0] rdata

);

logic [31:0] uart_mem [0:31];

always_ff @(posedge clk)
begin
    if(write)
        uart_mem[addr[4:0]] <= wdata;
end

assign rdata = uart_mem[addr[4:0]];

endmodule


// ============================================================
// GPIO
// ============================================================

module gpio_apb(

    input logic clk,
    input logic write,
    input logic read,
    input logic [7:0] addr,
    input logic [31:0] wdata,
    output logic [31:0] rdata

);

logic [31:0] gpio_mem [0:31];

always_ff @(posedge clk)
begin
    if(write)
        gpio_mem[addr[4:0]] <= wdata;
end

assign rdata = gpio_mem[addr[4:0]];

endmodule


// ============================================================
// TIMER
// ============================================================

module timer_apb(

    input logic clk,
    input logic write,
    input logic read,
    input logic [7:0] addr,
    input logic [31:0] wdata,
    output logic [31:0] rdata

);

logic [31:0] timer_mem [0:31];

always_ff @(posedge clk)
begin
    if(write)
        timer_mem[addr[4:0]] <= wdata;
    else
        timer_mem[addr[4:0]] <= timer_mem[addr[4:0]] + 1;
end

assign rdata = timer_mem[addr[4:0]];

endmodule


// ============================================================
// I2C
// ============================================================

module i2c_apb(

    input logic clk,
    input logic write,
    input logic read,
    input logic [7:0] addr,
    input logic [31:0] wdata,
    output logic [31:0] rdata

);

logic [31:0] i2c_mem [0:31];

always_ff @(posedge clk)
begin
    if(write)
        i2c_mem[addr[4:0]] <= wdata;
end

assign rdata = i2c_mem[addr[4:0]];

endmodule


// ============================================================
// TOP SYSTEM
// ============================================================

module top_memory_system(

    cpu_if vif

);

logic sel_ram;
logic sel_uart;
logic sel_gpio;
logic sel_timer;
logic sel_i2c;

logic [31:0] ram_rdata;
logic [31:0] uart_rdata;
logic [31:0] gpio_rdata;
logic [31:0] timer_rdata;
logic [31:0] i2c_rdata;

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
  

address_decoder dec(

    .addr(vif.addr),

    .sel_ram(sel_ram),
    .sel_uart(sel_uart),
    .sel_gpio(sel_gpio),
    .sel_timer(sel_timer),
    .sel_i2c(sel_i2c)

);

sram_model ram(

    .clk(vif.clk),
    .reset(vif.reset),
    .we(vif.write && sel_ram),
    .addr(vif.addr),
    .wdata(vif.wdata),
    .rdata(ram_rdata)

);

uart_apb uart(

    .clk(vif.clk),
    .write(vif.write & sel_uart),
    .read(vif.read),
    .addr(vif.addr),
    .wdata(vif.wdata),
    .rdata(uart_rdata)

);

gpio_apb gpio(

    .clk(vif.clk),
    .write(vif.write & sel_gpio),
    .read(vif.read),
    .wdata(vif.wdata),
    .addr(vif.addr),
    .rdata(gpio_rdata)

);

timer_apb timer(

    .clk(vif.clk),
    .write(vif.write & sel_timer),
    .read(vif.read),
    .wdata(vif.wdata),
    .addr(vif.addr),
    .rdata(timer_rdata)

);

i2c_apb i2c(

    .clk(vif.clk),
    .write(vif.write & sel_i2c),
    .read(vif.read),
    .wdata(vif.wdata),
    .addr(vif.addr),
    .rdata(i2c_rdata)

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

    vif.rdata = 32'hDEADBEEF;

    if(sel_ram)
        vif.rdata = ram_rdata;

    else if(sel_uart)
        vif.rdata = uart_rdata;

    else if(sel_gpio)
        vif.rdata = gpio_rdata;

    else if(sel_timer)
        vif.rdata = timer_rdata;

    else if(sel_i2c)
        vif.rdata = i2c_rdata;

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