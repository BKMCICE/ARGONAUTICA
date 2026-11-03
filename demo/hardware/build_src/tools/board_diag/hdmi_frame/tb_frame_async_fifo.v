`timescale 1ns/1ps
module tb_frame_async_fifo;
    parameter ADDR_BITS=2;
    reg rst_n=0,wclk=0,rclk=0,w_run=1,r_run=1;
    real w_half=3.367,r_half=5.0;
    always #(w_half) if(w_run) wclk=~wclk;
    always #(r_half) if(r_run) rclk=~rclk;
    reg wvalid=0,rready=0;
    reg [257:0] wdata=0;
    wire wready,rvalid,w_up,r_up;wire [257:0] rdata;
    hdmi_frame_async_fifo #(.ADDR_BITS(ADDR_BITS)) fifo(.*);
    integer received=0,accepted=0,epochs=0,total_received=0;
    reg [31:0] random_state=32'h13579bdf;
    reg [7:0] seed=0;
    reg held=0;reg [257:0] held_data=0;
    reg consume=1;
    function [257:0] pattern;
        input integer index;
        begin pattern={2'b01,{8{32'h12345678 ^ index ^ {24'b0,seed}}}};end
    endfunction
    always @(negedge rclk) begin
        random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
        rready=consume&&random_state[2:0]!=0;
    end
    always @(posedge wclk or negedge rst_n)
        if(!rst_n) accepted<=0;
        else if(wvalid&&wready) accepted<=accepted+1;
    always @(posedge rclk or negedge rst_n) begin
        if(!rst_n) begin received<=0;held<=0;end
        else begin
            if(held&&(!rvalid||rdata!==held_data)) $fatal(1,"FIFO stalled output changed");
            held<=rvalid&&!rready;held_data<=rdata;
            if(rvalid&&rready) begin
                if(rdata!==pattern(received)) $fatal(1,"FIFO ordering/lane/epoch mismatch epoch=%d index=%d",epochs,received);
                received<=received+1;total_received<=total_received+1;
            end
        end
    end
    task send;
        input integer index;
        begin
            @(negedge wclk);wvalid=1;wdata=pattern(index);
            do @(posedge wclk); while(!wready);
            @(negedge wclk);wvalid=0;
        end
    endtask
    task reset_epoch;
        input [7:0] value;
        begin
            rst_n=0;wvalid=0;seed=value;epochs=epochs+1;
            repeat(4) @(negedge rclk);rst_n=1;
            repeat(6) @(negedge rclk);
        end
    endtask
    integer n;
    initial begin
        reset_epoch(8'h11);
        for(n=0;n<12000;n=n+1) send(n);
        while(received!=12000) @(negedge rclk);
        // Invert clock ratio, force many pointer wraps and random stalls.
        w_half=6.113;r_half=2.731;reset_epoch(8'h52);
        for(n=0;n<12000;n=n+1) send(n);
        while(received!=12000) @(negedge rclk);
        // Fill exact capacity (RAM4 + prefetch1), then reset while W clock
        // stopped. Old output and RAM words must not leak into new epoch.
        consume=0;reset_epoch(8'h93);
        for(n=0;n<(1<<ADDR_BITS)+1;n=n+1) send(n);
        repeat(8) @(negedge rclk);
        if(wready||!rvalid) $fatal(1,"FIFO full capacity/control");
        @(negedge wclk);w_run=0;rst_n=0;
        repeat(4) @(negedge rclk);
        if(wready||rvalid||w_up||r_up) $fatal(1,"shared reset needs stopped clock");
        seed=8'hd4;epochs=epochs+1;consume=1;rst_n=1;
        repeat(6) @(negedge rclk);
        if(rvalid||w_up) $fatal(1,"stopped writer falsely ready or old data");
        w_run=1;
        for(n=0;n<12000;n=n+1) send(n);
        while(received!=12000) @(negedge rclk);
        if(accepted!=12000||total_received!=36000) $fatal(1,"accepted/delivered count mismatch");
        $display("FRAME_ASYNC_FIFO_PASS delivered=36000 ram_address_wraps=%0d+ clock_ratios=2 stalled_output=PASS full_capacity=%0d shared_reset_with_stopped_clock=PASS fresh_epochs=PASS",36000/(1<<ADDR_BITS),(1<<ADDR_BITS)+1);
        $finish;
    end
    initial begin #10000000;$fatal(1,"timeout");end
endmodule
