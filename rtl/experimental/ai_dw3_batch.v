// A53 isolated experiment. Not in any production/PDS source list.
// One channel, 1..8 interior horizontal outputs; row-major 3 x <=17 strip.
// Direct nine signed lanes, resident weights/Q24, atomic packed publication.
module ai_dw3_batch (
    input wire clk,rst_n,req,we,conflict,
    input wire [3:0] be,
    input wire [31:0] addr,wdata,
    output reg [31:0] rdata,
    output wire ready,busy
);
    localparam IDLE=0,DOT=1,SUM=2,QSTART=3,QWAIT=4,DRAIN=5;
    reg [2:0] state;
    reg error,done,config_valid,mult_valid,bias_valid;
    reg [2:0] weight_valid;
    reg [14:0] strip_valid;
    reg [5:0] config_word;
    reg [1:0] wi,ri;
    reg [3:0] si,pixel;
    reg [4:0] column;
    reg [9:0] timer;
    reg [31:0] weights[0:2],strip[0:14],packed_words[0:1];
    reg signed [31:0] multiplier,bias,acc;
    reg signed [15:0] products[0:8];
    reg [31:0] dots,tasks,items;
    wire [3:0] count=config_word[3:0];
    wire [4:0] width=5'd3+((count-1'b1) << config_word[4]);
    wire [4:0] rounded_width=width+5'd3;
    wire [2:0] words=rounded_width[4:2];
    wire [3:0] packed_count=(count+4'd3)>>2;
    wire qbusy,qdone,qerror;
    wire signed [7:0] qvalue;
    wire published=done&&!error&&!busy;
    reg signed [31:0] dot_sum;
    reg strip_complete;
    integer i,j,k;
    assign ready=1'b1;
    assign busy=state!=IDLE;
    ai_q24_post post(.clk(clk),.rst_n(rst_n),.start(state==QSTART),
        .acc(acc),.mult(multiplier),.bias(bias),.leaky(config_word[5]),
        .busy(qbusy),.done(qdone),.error(qerror),.value(qvalue));
    function signed [7:0] strip_byte(input integer row,input integer col);
        begin strip_byte=$signed(strip[row*5+col/4][(col%4)*8+:8]);end
    endfunction
    function signed [7:0] weight_byte(input integer n);
        begin weight_byte=$signed(weights[n/4][(n%4)*8+:8]);end
    endfunction
    always @* begin
        dot_sum=0;
        for(integer n=0;n<9;n=n+1)dot_sum=dot_sum+$signed({{16{products[n][15]}},products[n]});
        strip_complete=1;
        for(integer row=0;row<3;row=row+1)
            for(integer col=0;col<5;col=col+1)
                if(col<words && !strip_valid[row*5+col])strip_complete=0;
        rdata=0;
        case(addr[11:0])
            'h300:rdata=32'h41353331; // A531, read-only
            'h304:rdata={29'b0,error,done,busy};
            'h308:rdata={26'b0,config_word};
            'h30c:rdata=multiplier;
            'h310:rdata=bias;
            'h314:rdata={30'b0,wi};
            'h31c:rdata={28'b0,si};
            'h328:rdata={30'b0,ri};
            'h32c:if(published && {2'b0,ri}<packed_count)rdata=packed_words[ri[0]];
            'h330:rdata=published?{28'b0,count}:0;
            'h334:rdata=dots;
            'h338:rdata=tasks;
            'h33c:rdata=items;
            default:;
        endcase
    end
    task fault;
        begin error<=1;done<=0;if(busy)state<=DRAIN;end
    endtask
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=IDLE;error<=0;done<=0;config_valid<=0;config_word<=0;
            mult_valid<=0;bias_valid<=0;weight_valid<=0;strip_valid<=0;
            wi<=0;si<=0;ri<=0;pixel<=0;column<=0;timer<=0;
            multiplier<=0;bias<=0;acc<=0;dots<=0;tasks<=0;items<=0;
            for(i=0;i<3;i=i+1)weights[i]<=0;
            for(i=0;i<15;i=i+1)strip[i]<=0;
            for(i=0;i<2;i=i+1)packed_words[i]<=0;
            for(i=0;i<9;i=i+1)products[i]<=0;
        end else begin
            if(busy)timer<=timer+1'b1;
            case(state)
                DOT:begin
                    for(j=0;j<3;j=j+1)for(k=0;k<3;k=k+1)
                        products[j*3+k]<=strip_byte(j,int'(column)+k)*weight_byte(j*3+k);
                    dots<=dots+1;state<=SUM;
                end
                SUM:begin acc<=dot_sum;state<=QSTART;end
                QSTART:state<=QWAIT;
                QWAIT:if(qdone)begin
                    if(qerror)fault();
                    else begin
                        packed_words[pixel[2]] <= packed_words[pixel[2]] |
                            ({24'b0,qvalue} << (pixel[1:0]*8));
                        items<=items+1;
                        if(pixel+1==count)begin done<=1;state<=IDLE;end
                        else begin pixel<=pixel+1;column<=column+(config_word[4]?2:1);state<=DOT;end
                    end
                end
                DRAIN:if(!qbusy)state<=IDLE;
                default:;
            endcase
            // All software writes during ownership and illegal result reads
            // poison the whole task. No partial result is publicly visible.
            if(conflict)fault();
            if(busy && timer==511)fault();
            if(req)begin
                if(addr[1:0]!=0 || (we&&be!=15))fault();
                else if(we)begin
                    if(busy)fault();
                    else if(addr[11:0]=='h304 && (wdata==2||wdata==4))begin
                        error<=0;done<=0;strip_valid<=0;si<=0;ri<=0;
                        packed_words[0]<=0;packed_words[1]<=0;
                        if(wdata==2)begin
                            weight_valid<=0;mult_valid<=0;bias_valid<=0;
                            config_valid<=0;config_word<=0;wi<=0;
                        end
                    end else if(error)fault();
                    else begin
                        case(addr[11:0])
                            'h304:begin
                                if(wdata!=1 || !config_valid || !mult_valid || !bias_valid ||
                                   weight_valid!=7 || !strip_complete || qbusy)fault();
                                else begin
                                    done<=0;packed_words[0]<=0;packed_words[1]<=0;ri<=0;
                                    pixel<=0;column<=0;timer<=0;tasks<=tasks+1;state<=DOT;
                                    strip_valid<=0; // every task must reseed all rows
                                end
                            end
                            'h308:begin
                                done<=0;
                                if(wdata[31:6]!=0 || wdata[3:0]<1 || wdata[3:0]>8)begin config_valid<=0;fault();end
                                else begin config_word<=wdata[5:0];config_valid<=1;strip_valid<=0;end
                            end
                            'h30c:begin multiplier<=wdata;mult_valid<=1;done<=0;end
                            'h310:begin bias<=wdata;bias_valid<=1;done<=0;end
                            'h314:if(wdata<3)wi<=wdata[1:0];else fault();
                            'h318:if(wi<3)begin weights[wi]<=wdata;weight_valid[wi]<=1;wi<=wi+1;done<=0;end else fault();
                            'h31c:if(wdata<15)si<=wdata[3:0];else fault();
                            'h320:if(si<15)begin strip[si]<=wdata;strip_valid[si]<=1;si<=si+1;done<=0;end else fault();
                            'h328:if(wdata<2)ri<=wdata[1:0];else fault();
                            default:fault();
                        endcase
                    end
                end else if(addr[11:0]=='h32c)begin
                    if(!published || {2'b0,ri}>=packed_count)fault();else ri<=ri+1;
                end else case(addr[11:0])
                    'h300,'h304,'h308,'h30c,'h310,'h314,'h31c,'h328,'h330,'h334,'h338,'h33c:;
                    default:fault();
                endcase
            end
        end
    end
endmodule
