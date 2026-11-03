`timescale 1ns/1ps
// Real original hardware ROM, complete R SoC and unmodified UART at DIV868.
// DDR PHY/native RAM is the only silicon model; no internal force/preload.
module tb_transaction_boot_uart;
    parameter BOOT="",FRAME_HEX="",TCM_HEX="";
    parameter integer FRAME_BYTES=1,PAYLOAD_BYTES=1,TCM_WORDS=4;
    parameter [31:0] TCM_SOURCE_ADDR=32'h80000000;
    localparam integer UART_DIV=868,MAX_CPU_CYCLES=5000000;
    reg sys_clk=0,uart_rx=1;always #10 sys_clk=~sys_clk;
    wire [7:0] led;wire uart_tx;tri1 hdmi_sda,hdmi_rx_iic_sda;
    pangu50k_capture_top #(.RAM_INIT_FILE(BOOT)) top(
        .sys_clk(sys_clk),.led(led),.uart_rx(uart_rx),.uart_tx(uart_tx),
        .hdmi_rx_pixclk(1'b0),.hdmi_rx_de(1'b0),.hdmi_rx_hs(1'b0),.hdmi_rx_vs(1'b0),
        .hdmi_rx_r(8'b0),.hdmi_rx_g(8'b0),.hdmi_rx_b(8'b0),.hdmi_rx_iic_scl(),.hdmi_rx_iic_sda(hdmi_rx_iic_sda),
        .hdmi_rst_n(),.hdmi_scl(),.hdmi_sda(hdmi_sda),.hdmi_pclk(),.hdmi_de(),.hdmi_hs(),.hdmi_vs(),.hdmi_r(),.hdmi_g(),.hdmi_b(),
        .mem_rst_n(),.mem_ck(),.mem_ck_n(),.mem_cke(),.mem_cs_n(),.mem_ras_n(),.mem_cas_n(),.mem_we_n(),.mem_odt(),
        .mem_a(),.mem_ba(),.mem_dqs(),.mem_dqs_n(),.mem_dq(),.mem_dm());
    reg [7:0] frame[0:FRAME_BYTES-1];reg [31:0] tcm_expected[0:TCM_WORDS-1];
    reg [87:0] banner_window=0;reg [31:0] tail_window=0;reg [7:0] serial_byte=0;
    integer wire_log,wire_bytes=0,boot_count=0,go_count=0,bit_number,k;
    reg boot_seen=0,go_seen=0;reg [2047:0] wire_log_path;
    integer cpu_cycles=0,boot_cycle=-1,send_cycle=-1,send_done_cycle=-1,go_cycle=-1;
    integer first_ddr_retire=-1,first_tcm_retire=-1,tcm_retire_count=0,tcm_writes=0,tcm_reads=0,gpio_a6_writes=0;
    integer ddr_writes=0,ddr_reads=0,fences_consumed=0;
    reg [31:0] last_tcm_pc=0;
    initial begin
        $readmemh(FRAME_HEX,frame);$readmemh(TCM_HEX,tcm_expected);
        if(!$value$plusargs("uart_log=%s",wire_log_path))$fatal(1,"missing UART log path");
        wire_log=$fopen(wire_log_path,"wb");if(!wire_log)$fatal(1,"cannot create wire UART log");
    end
    // Decode only the physical TX wire: start,8 data bits LSB-first,stop.
    initial forever begin
        @(negedge uart_tx);
        repeat(UART_DIV+UART_DIV/2)@(negedge top.ui_clk);
        for(bit_number=0;bit_number<8;bit_number=bit_number+1)begin
            serial_byte[bit_number]=uart_tx;repeat(UART_DIV)@(negedge top.ui_clk);
        end
        if(uart_tx!==1'b1)$fatal(1,"UART TX bad8N1 stop");
        $fwrite(wire_log,"%c",serial_byte);$fflush(wire_log);wire_bytes=wire_bytes+1;
        banner_window={banner_window[79:0],serial_byte};tail_window={tail_window[23:0],serial_byte};
        if(banner_window==88'h52563332424f4f54310d0a)begin
            boot_count=boot_count+1;boot_seen=1;boot_cycle=cpu_cycles;$display("R_BOOT_UART_BANNER cycle=%0d",cpu_cycles);
        end
        if(tail_window=="BAD ")$fatal(1,"boot ROM rejected frame");
        if(tail_window==32'h474f0d0a)begin
            go_count=go_count+1;go_seen=1;go_cycle=cpu_cycles;$display("R_BOOT_UART_GO cycle=%0d",cpu_cycles);
        end
    end
    task send_byte;
        input [7:0] value;integer b;
        begin
            @(negedge top.ui_clk);uart_rx=0;repeat(UART_DIV)@(negedge top.ui_clk);
            for(b=0;b<8;b=b+1)begin uart_rx=value[b];repeat(UART_DIV)@(negedge top.ui_clk);end
            uart_rx=1;repeat(UART_DIV)@(negedge top.ui_clk);
        end
    endtask
    initial begin
        wait(boot_seen);send_cycle=cpu_cycles;
        for(k=0;k<FRAME_BYTES;k=k+1)send_byte(frame[k]);
        send_done_cycle=cpu_cycles;$display("R_BOOT_UART_UPLOAD_SENT frame_bytes=%0d cycle=%0d",FRAME_BYTES,cpu_cycles);
    end
    always @(posedge top.ui_clk)if(top.reset_sync[3])begin
        cpu_cycles=cpu_cycles+1;
        if(cpu_cycles>=MAX_CPU_CYCLES)$fatal(1,"boot UART timeout cycles=%0d pc=%h GPIO=%h boot=%0d GO=%0d",cpu_cycles,top.u_soc.u_core.exmem_pc,led,boot_seen,go_seen);
        if(boot_seen&&top.u_soc.u_uart.div!==UART_DIV)$fatal(1,"hardware UART divisor altered");
        if(top.awvalid&&top.awready)ddr_writes=ddr_writes+1;
        if(top.arvalid&&top.arready)ddr_reads=ddr_reads+1;
        if(top.u_soc.fencei_req&&top.u_soc.fencei_done&&top.u_soc.u_core.mem_adv)fences_consumed=fences_consumed+1;
        if(top.u_soc.u_core.mem_adv&&top.u_soc.u_core.mem_commit)begin
            if(top.u_soc.u_core.exmem_pc>=32'h80000000&&top.u_soc.u_core.exmem_pc<32'h80000000+PAYLOAD_BYTES&&first_ddr_retire<0)first_ddr_retire=cpu_cycles;
            if(top.u_soc.u_core.exmem_pc>=32'h8000&&top.u_soc.u_core.exmem_pc<32'h8000+TCM_WORDS*4)begin
                if(first_tcm_retire<0)first_tcm_retire=cpu_cycles;
                last_tcm_pc=top.u_soc.u_core.exmem_pc;tcm_retire_count=tcm_retire_count+1;
            end
        end
        if(top.u_soc.dmem_consume&&top.u_soc.txn_addr>=32'h8000&&top.u_soc.txn_addr<32'h8000+TCM_WORDS*4)begin
            if(top.u_soc.txn_we)begin
                if(top.u_soc.txn_be!=15||top.u_soc.txn_wdata!==tcm_expected[(top.u_soc.txn_addr-32'h8000)>>2])$fatal(1,"TCM copied word mismatch");
                tcm_writes=tcm_writes+1;
            end else begin
                if(top.u_soc.dmem_rdata!==tcm_expected[(top.u_soc.txn_addr-32'h8000)>>2])$fatal(1,"TCM CPU readback mismatch");
                tcm_reads=tcm_reads+1;
            end
        end
        if(top.u_soc.s_req[3]&&top.u_soc.s_we&&top.u_soc.s_addr==32'h40001000)begin
            if(top.u_soc.s_wdata==8'he1)$fatal(1,"payload signaled copy/readback failure");
            if(top.u_soc.s_wdata==8'ha6)gpio_a6_writes=gpio_a6_writes+1;
        end
    end
    initial begin
        wait(go_seen&&led==8'ha6&&tcm_retire_count>=3);
        repeat(8)@(negedge top.ui_clk);
        wait(top.u_soc.u_core.exmem_valid&&top.u_soc.u_core.exmem_pc>=32'h8000&&top.u_soc.u_core.exmem_pc<32'h8000+TCM_WORDS*4);
        if(boot_count!=1||go_count!=1||gpio_a6_writes!=1||tcm_writes!=TCM_WORDS||tcm_reads!=TCM_WORDS||
           first_ddr_retire<0||first_tcm_retire<=first_ddr_retire||ddr_writes==0||ddr_reads==0||fences_consumed<2||send_cycle<boot_cycle)
            $fatal(1,"boot UART evidence counts failed boot%0d go%0d A6%0d copy%0d read%0d ddr%0d/%0d fence%0d",boot_count,go_count,gpio_a6_writes,tcm_writes,tcm_reads,ddr_writes,ddr_reads,fences_consumed);
        $fclose(wire_log);
        $display("H04R_BOOT_UART_TINY_TCM_EXECUTION_PASS cpu_cycles=%0d uart_divisor=%0d payload_bytes=%0d frame_bytes=%0d tcm_bytes=%0d tcm_writes=%0d tcm_readbacks=%0d TCM_retired=%0d GPIO_A6_writes=%0d boot_count=%0d GO_count=%0d boot_cycle=%0d send_cycle=%0d send_done_cycle=%0d GO_cycle=%0d first_DDR_retire=%0d first_TCM_retire=%0d last_TCM_PC=%08h native_AW=%0d native_AR=%0d fences=%0d",cpu_cycles,UART_DIV,PAYLOAD_BYTES,FRAME_BYTES,TCM_WORDS*4,tcm_writes,tcm_reads,tcm_retire_count,gpio_a6_writes,boot_count,go_count,boot_cycle,send_cycle,send_done_cycle,go_cycle,first_ddr_retire,first_tcm_retire,last_tcm_pc,ddr_writes,ddr_reads,fences_consumed);
        $finish;
    end
    initial begin #52000000;$fatal(1,"boot UART wall-simulation bound");end
endmodule
