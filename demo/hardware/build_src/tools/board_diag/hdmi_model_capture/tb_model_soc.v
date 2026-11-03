`timescale 1ns/1ps
module tb_model_soc;
    parameter IMAGE="", IDENTITY_ONLY=0;
    reg sys_clk=0,hdmi_rx_pixclk=0,uart_rx=1;
    always #10 sys_clk=~sys_clk;always #3.367 hdmi_rx_pixclk=~hdmi_rx_pixclk;
    wire [7:0] led;wire uart_tx;
    tri1 hdmi_sda,hdmi_rx_iic_sda;
    reg hdmi_rx_de=0,hdmi_rx_hs=0,hdmi_rx_vs=0;
    reg [7:0] hdmi_rx_r=0,hdmi_rx_g=0,hdmi_rx_b=0;
    wire hdmi_pclk,hdmi_de,hdmi_hs,hdmi_vs;wire [7:0] hdmi_r,hdmi_g,hdmi_b;
    pangu50k_capture_top #(.RAM_INIT_FILE(IMAGE),.CAPTURE_W(1920),.CAPTURE_H(1080),.FIFO_ADDR_BITS(9),.FRONTEND_GEO_INTERVAL(50000),.FRONTEND_HTOTAL(2200),.FRONTEND_VTOTAL(1125)) top(
        .sys_clk(sys_clk),.led(led),.uart_rx(uart_rx),.uart_tx(uart_tx),
        .hdmi_rx_pixclk(hdmi_rx_pixclk),.hdmi_rx_de(hdmi_rx_de),.hdmi_rx_hs(hdmi_rx_hs),.hdmi_rx_vs(hdmi_rx_vs),
        .hdmi_rx_r(hdmi_rx_r),.hdmi_rx_g(hdmi_rx_g),.hdmi_rx_b(hdmi_rx_b),
        .hdmi_rx_iic_scl(),.hdmi_rx_iic_sda(hdmi_rx_iic_sda),
        .hdmi_rst_n(),.hdmi_scl(),.hdmi_sda(hdmi_sda),.hdmi_pclk(hdmi_pclk),
        .hdmi_de(hdmi_de),.hdmi_hs(hdmi_hs),.hdmi_vs(hdmi_vs),.hdmi_r(hdmi_r),.hdmi_g(hdmi_g),.hdmi_b(hdmi_b),
        .mem_rst_n(),.mem_ck(),.mem_ck_n(),.mem_cke(),.mem_cs_n(),.mem_ras_n(),.mem_cas_n(),.mem_we_n(),.mem_odt(),
        .mem_a(),.mem_ba(),.mem_dqs(),.mem_dqs_n(),.mem_dq(),.mem_dm());
    wire ov,ob,oe;wire [31:0] ow,os,oa;
    // Only silicon boundaries replaced: DDR PHY native RAM model and RX I2C
    // initialization/frequency qualified levels; TX is the real wire protocol. Geometry/startup, pixel loop, FIFO,
    // CPU, complete SoC peripherals and all their buses run real RTL.
    initial begin
        force top.frontend.rx_init=1;force top.frontend.edid_ok=1;force top.frontend.setting_done=1;
        force top.frontend.fault=0;
        force top.frontend.frequency_update=1;force top.frontend.frequency_sample=32'h00035800;
        force top.frontend.observation_valid=ov;force top.frontend.observation_busy=ob;force top.frontend.last_observation_error=oe;
        force top.frontend.observation_raw=ow;force top.frontend.observation_sequence=os;force top.frontend.observation_age=oa;
    end
    t_observation_stimulus observer(.clk(sys_clk),.rst_n(top.frontend.rst_n),.enable(1'b1),.good(1'b1),.error(1'b0),
        .valid(ov),.busy(ob),.last_error(oe),.raw(ow),.seq(os),.age(oa));
    // Real formal TX writes and ACKs at the external SDA/SCL boundary.
    // No force on TX done/error, phase, geometry, capture_ready or OUT pins.
    defparam top.frontend.u_hdmi_init.QUARTER_CYCLES=2,
             top.frontend.u_hdmi_init.RESET_CYCLES=4,
             top.frontend.u_hdmi_init.WRITE_GAP_CYCLES=2,
             top.frontend.u_hdmi_init.SETTLE_CYCLES=6;
    wire [31:0] tx_starts,tx_stops,tx_bytes;
    q_tx_wire_slave tx_fixture(.scl(top.hdmi_scl),.sda(hdmi_sda),
        .reset_n(top.frontend.tx_software_reset_n),.ack_enable(1'b1),
        .starts(tx_starts),.stops(tx_stops),.bytes(tx_bytes));
    reg physical_released=0;
    always @(posedge top.hdmi_rst_n)physical_released=1;
    always @(negedge top.hdmi_rst_n)if(physical_released)$fatal(1,"SoC TX reasserted physical RX reset");
    always @(negedge sys_clk)if(top.frontend.rst_n && top.frontend.status_code!==led)
        $fatal(1,"Real GPIO led not wired to status page");
    // Full1080p stream; all source rows are real clocks, never a320x320 shortcut.
    integer x,y,xx,yy,sw_irq=0,tim_irq=0,gpio_irq=0,uart_irq=0,traps=0;
    initial forever for(y=0;y<1125;y=y+1)for(x=0;x<2200;x=x+1)begin
        @(posedge hdmi_rx_pixclk);#0.1;
        hdmi_rx_hs=x<44;hdmi_rx_vs=y<5;hdmi_rx_de=x>=192&&x<2112&&y>=41&&y<1121;
        xx=x-192;yy=y-41;
        hdmi_rx_r=xx*7+yy*3+23;hdmi_rx_g=xx*11+yy*5+83+23;hdmi_rx_b=xx*13+yy*17+167+23;
    end
    always @(posedge top.ui_clk) if(top.reset_sync[3])begin
        if(top.u_soc.irq_sw)sw_irq=sw_irq+1;
        if(top.u_soc.irq_tim)tim_irq=tim_irq+1;
        if(top.u_soc.gpio_irq&&top.u_soc.u_core.irq_external)gpio_irq=gpio_irq+1;
        if(top.u_soc.uart_irq&&top.u_soc.u_core.irq_external)uart_irq=uart_irq+1;
        if(top.u_soc.ev_tr)traps=traps+1;
    end
    initial begin
        wait(led==8'h31);force top.u_soc.u_gpio.gpio_in=8'hfe;
        repeat(100)@(negedge top.ui_clk);force top.u_soc.u_gpio.gpio_in=8'hff;
    end
    integer txbit,rxbit;reg [7:0] tx_value=0;reg tx_checked=0;
    initial begin
        @(negedge uart_tx);repeat(24)@(negedge top.ui_clk);
        for(txbit=0;txbit<8;txbit=txbit+1)begin
            tx_value[txbit]=uart_tx;repeat(16)@(negedge top.ui_clk);
        end
        if(tx_value!=8'h55||uart_tx!=1)$fatal(1,"UART TX physical bit stream");tx_checked=1;
    end
    initial begin
        wait(led==8'h32);repeat(20)@(negedge top.ui_clk);
        uart_rx=0;repeat(16)@(negedge top.ui_clk);
        for(rxbit=0;rxbit<8;rxbit=rxbit+1)begin uart_rx=(8'ha6>>rxbit)&1;repeat(16)@(negedge top.ui_clk);end
        uart_rx=1;repeat(32)@(negedge top.ui_clk);
    end
    initial begin
        wait(led==8'ha5||led==8'he0);
        if(led!=8'ha5)$fatal(1,"SoC program failed code=%h pc=%h",top.u_soc.u_boot_ram.mem[16'h7000>>2],top.u_soc.u_core.imem_addr);
        if(IDENTITY_ONLY) begin
            if(top.u_soc.frame_memory.command_error!=0||top.u_soc.frame_memory.sequence_number!=0)
                $fatal(1,"identity-only must leave complete command state unchanged");
            $display("H04Z_CPU_IDENTITY_ONLY_PASS six_readonly_words=PASS full_and_byte_writes_no_effect=PASS old_adjacent_decode=PASS");
            $finish;
        end
        if(top.u_soc.u_boot_ram.mem[16'h7004>>2]!=32'h4119edc5||top.u_soc.u_boot_ram.mem[16'h7008>>2]!=7)
            $fatal(1,"SoC FNV/trap metadata");
        if(sw_irq==0||tim_irq==0||gpio_irq==0||uart_irq==0||traps!=1||!tx_checked)
            $fatal(1,"peripheral IRQ/UART/trap routing missing %d %d %d %d %d tx%0d",sw_irq,tim_irq,gpio_irq,uart_irq,traps,tx_checked);
        if(top.u_soc.AI_LATCH_SHAPE!=1 || top.u_soc.u_ai.block8_quant_engine.u_impl.LATCH_SHAPE_VALID!=1 ||
           top.u_soc.u_ai.block8_quant_engine.u_impl.core.LATCH_SHAPE_VALID!=1)$fatal(1,"Candidate shape profile not enabled");
        repeat(10)@(negedge sys_clk);
        if(!top.frontend.tx_done||top.frontend.tx_error||tx_starts!=49||tx_stops!=49||tx_bytes!=196||top.frontend.u_hdmi_video.code_sync!==led)
            $fatal(1,"SoC real TX init/status GPIO missing");
        $display("H04Z_FULL_SOC_BOARD_BOUNDARY_PASS gpio=PASS uart55_a6=PASS software_timer_gpio_uart_irq_routes=PASS perf_cache_stats=PASS AI_dot18_A481=PASS AI_raw_shape_guards_cycles3=PASS frontend_snapshot_CPU_MMIO_frozen_seq1=PASS DDR_fence17to34=PASS frontend_geometry_startup_and_unified_sample=PASS RAW320_identity_CPU_MMIO=PASS first384B_FNV=4119edc5 cause7_mret=PASS single_cpu_UART=PASS");
        $finish;
    end
    always @(posedge hdmi_rx_vs) $display("Z_SOC_FRAME time=%0t ready=%b state=%0d led=%h",$time,top.capture_ready,top.u_soc.frame_memory.state,led);
    initial begin #250000000;$fatal(1,"timeout led%h pc%h capturestate%0d",led,top.u_soc.u_core.imem_addr,top.u_soc.frame_memory.state);end
endmodule
