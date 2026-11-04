`timescale 1ns/1ps
// Pure streaming algorithm; causal top/left padding; mode sampled only at SOF.
module comic_core #(parameter integer W=1280,H=720,AW=11,AV=10,THRESH=100,QBITS=3,BLOCK=8,LOG2B=3,DEBUG_ENABLE=0,VISUAL_TUNE=0)(
 input wire clk,rst,sof,de_in,input wire[23:0] vin,input wire[2:0] mode,
 output reg de_out,output reg[23:0] vout,output wire de_s0,
 output reg[23:0] dbg_smooth,dbg_raw,output reg[7:0] dbg_gray,output reg[11:0] dbg_mag,output reg dbg_edge);
 function[7:0] smooth;
  input[7:0] a,b,c,d,e,f,g,h,i;reg[9:0] r0,r1,r2,v;
  begin r0=a+{b,1'b0}+c+10'd2;r1=d+{e,1'b0}+f+10'd2;r2=g+{h,1'b0}+i+10'd2;
   v=r0[9:2]+{r1[9:2],1'b0}+r2[9:2]+10'd2;smooth=v[9:2];end
 endfunction
 function[7:0] gray;input[23:0] rgb;reg[15:0] sum;
  begin sum=77*rgb[23:16]+150*rgb[15:8]+29*rgb[7:0];gray=sum[15:8];end endfunction
 function[7:0] quant;input[7:0] c;
  begin if(VISUAL_TUNE)quant={c[7:4],c[7:4]};
   else case(QBITS)3:quant={c[7:5],c[7:5],c[7:6]};4:quant={c[7:4],c[7:4]};default:quant={4{c[7:6]}};endcase end endfunction
 reg[2:0] frame_mode;always @(posedge clk)if(rst)frame_mode<=0;else if(sof)frame_mode<=mode;
 wire vw;wire[23:0] p[0:8];wire[AW-1:0] x;wire[AV-1:0] y;
 win3x3 #(.W(W),.H(H),.AW(AW),.AV(AV),.DW(24)) wrgb(
 .clk(clk),.rst(rst),.sof(sof),.de_in(de_in),.din(vin),.de_win(vw),
 .w00(p[0]),.w01(p[1]),.w02(p[2]),.w10(p[3]),.w11(p[4]),.w12(p[5]),.w20(p[6]),.w21(p[7]),.w22(p[8]),.xo(x),.yo(y));
 wire[23:0] sm={smooth(p[0][23:16],p[1][23:16],p[2][23:16],p[3][23:16],p[4][23:16],p[5][23:16],p[6][23:16],p[7][23:16],p[8][23:16]),
 smooth(p[0][15:8],p[1][15:8],p[2][15:8],p[3][15:8],p[4][15:8],p[5][15:8],p[6][15:8],p[7][15:8],p[8][15:8]),
 smooth(p[0][7:0],p[1][7:0],p[2][7:0],p[3][7:0],p[4][7:0],p[5][7:0],p[6][7:0],p[7][7:0],p[8][7:0])};
 reg[23:0] blocks[0:(W+BLOCK-1)/BLOCK-1],hold_pixel;
 wire block_start=((x&(BLOCK-1))==0),block_top=((y&(BLOCK-1))==0);
 wire[23:0] mosaic=block_start?(block_top?p[8]:blocks[x>>LOG2B]):hold_pixel;
 reg[23:0] raw_s,sm_s,pix_s;reg valid_s,sof_s;
 always @(posedge clk)begin
  if(rst)begin raw_s<=0;sm_s<=0;pix_s<=0;valid_s<=0;hold_pixel<=0;sof_s<=0;end
  else begin
   sof_s<=sof;valid_s<=vw && !sof;
   if(vw && !sof)begin
    raw_s<=p[8];sm_s<=sm;pix_s<=mosaic;
    if(block_start)begin hold_pixel<=mosaic;if(block_top)blocks[x>>LOG2B]<=p[8];end
   end
  end
 end
 wire vg;wire[7:0] g[0:8];wire[AW-1:0] gxpos;wire[AV-1:0] gypos;
 win3x3 #(.W(W),.H(H),.AW(AW),.AV(AV),.DW(8)) wgray(
 // Immediate SOF cancels gray-window valid state as well as the RGB pipeline.
 // Delayed SOF still aligns the new gray stream's coordinates on the next cycle.
 .clk(clk),.rst(rst || sof),.sof(sof_s),.de_in(valid_s),.din(gray(sm_s)),.de_win(vg),
 .w00(g[0]),.w01(g[1]),.w02(g[2]),.w10(g[3]),.w11(g[4]),.w12(g[5]),.w20(g[6]),.w21(g[7]),.w22(g[8]),.xo(gxpos),.yo(gypos));
 reg[23:0] r0,r1,s0,s1,b0,b1;
 always @(posedge clk)begin
  if(rst || sof)begin r0<=0;r1<=0;s0<=0;s1<=0;b0<=0;b1<=0;end
  else begin r0<=raw_s;r1<=r0;s0<=sm_s;s1<=s0;b0<=pix_s;b1<=b0;end
 end
 wire[9:0] sa=g[2]+{g[5],1'b0}+g[8],sb=g[0]+{g[3],1'b0}+g[6];
 wire[9:0] sc=g[6]+{g[7],1'b0}+g[8],sd=g[0]+{g[1],1'b0}+g[2];
 wire signed[10:0] dx=$signed({1'b0,sa})-$signed({1'b0,sb}),dy=$signed({1'b0,sc})-$signed({1'b0,sd});
 wire[10:0] ax=dx[10]?-dx:dx,ay=dy[10]?-dy:dy;
 wire[11:0] mag={1'b0,ax}+{1'b0,ay};
 // Separate fine line-art from the stronger contour overlay on tonal images.
 // Defaults preserve the accepted implementation exactly.
 wire edge_on=mag>(VISUAL_TUNE?160:THRESH);
 wire line_edge=mag>(VISUAL_TUNE?48:THRESH);
 wire[23:0] qrgb={quant(s1[23:16]),quant(s1[15:8]),quant(s1[7:0])};
 wire[7:0] lum=gray(s1),tone=VISUAL_TUNE?{lum[7:5],5'b10000}:(lum<85)?0:(lum<170)?128:255;
 always @(posedge clk)begin
  if(rst || sof)begin de_out<=0;vout<=0;dbg_raw<=0;dbg_smooth<=0;dbg_gray<=0;dbg_mag<=0;dbg_edge<=0;end
  else begin
   de_out<=vg;
   if(vg)begin
    case(frame_mode)
     0:vout<=r1;1:vout<=edge_on?24'h000000:{tone,tone,tone};2:vout<=line_edge?24'h000000:24'hffffff;
     3:vout<=qrgb;4:vout<=b1;default:vout<=edge_on?24'h000000:qrgb;
    endcase
    dbg_raw<=r1;dbg_smooth<=DEBUG_ENABLE?s1:0;dbg_gray<=DEBUG_ENABLE?lum:0;dbg_mag<=DEBUG_ENABLE?mag:0;dbg_edge<=DEBUG_ENABLE?edge_on:0;
   end
  end
 end
 assign de_s0=vw;
 initial begin
  if(BLOCK<1 || BLOCK!=(1<<LOG2B))$error("BLOCK must equal 1<<LOG2B");
  if(QBITS!=2 && QBITS!=3 && QBITS!=4)$error("QBITS must be 2,3,4");
 end
endmodule
