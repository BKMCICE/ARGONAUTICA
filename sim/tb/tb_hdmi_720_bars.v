`timescale 1ns/1ps
module tb_hdmi_720_bars;
    reg clk=0, rst_n=0;
    always #5 clk=~clk;
    wire hs,vs,de;
    wire [7:0] r,g,b;
    hdmi_720_bars dut(.clk(clk),.rst_n(rst_n),.hs(hs),.vs(vs),.de(de),.r(r),.g(g),.b(b));
    integer active=0, hsync=0, vsync=0, n, i;
    integer colors[0:7];
    initial begin
        for(i=0;i<8;i=i+1) colors[i]=0;
        repeat(4) @(negedge clk);
        rst_n=1;
        repeat(1650*750) begin
            @(negedge clk);
            if(hs) hsync=hsync+1;
            if(vs) vsync=vsync+1;
            if(de) begin
                active=active+1;
                case({r,g,b})
                    24'hffffff: colors[0]=colors[0]+1;
                    24'hffff00: colors[1]=colors[1]+1;
                    24'h00ffff: colors[2]=colors[2]+1;
                    24'h00ff00: colors[3]=colors[3]+1;
                    24'hff00ff: colors[4]=colors[4]+1;
                    24'hff0000: colors[5]=colors[5]+1;
                    24'h0000ff: colors[6]=colors[6]+1;
                    24'h000000: colors[7]=colors[7]+1;
                    default: $fatal(1,"unexpected active RGB %h",{r,g,b});
                endcase
            end else if ({r,g,b} !== 24'h0) $fatal(1,"blanking RGB not zero");
        end
        if(active!=1280*720 || hsync!=40*750 || vsync!=5*1650)
            $fatal(1,"bad frame active=%d hs=%d vs=%d",active,hsync,vsync);
        for(i=0;i<8;i=i+1) if(colors[i]!=160*720) $fatal(1,"bar %d pixels=%d",i,colors[i]);
        $display("HDMI_720_BARS_PASS active=%0d hs_high=%0d vs_high=%0d each_bar=%0d",active,hsync,vsync,colors[0]);
        $finish;
    end
endmodule
