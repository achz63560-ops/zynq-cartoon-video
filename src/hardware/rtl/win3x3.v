`timescale 1ns/1ps
// Causal window: tap[r,c]=pixel[max(y-2+r,0),max(x-2+c,0)].
// Only accepted pixels shift horizontal history. SOF can precede first pixel.
module win3x3 #(parameter integer W=1280,H=720,AW=11,AV=10,DW=24,XOFF=0,YOFF=0)(
 input wire clk,rst,sof,de_in,input wire[DW-1:0] din,
 output reg de_win,output reg[DW-1:0] w00,w01,w02,w10,w11,w12,w20,w21,w22,
 output reg[AW-1:0] xo,output reg[AV-1:0] yo);
 reg[DW-1:0] b0[0:W-1],b1[0:W-1],b2[0:W-1];
 reg[AW-1:0] x,sx;reg[AV-1:0] y,sy;reg[1:0] bank,sbank;reg pending;
 reg[DW-1:0] q0,q1,q2,sd,t1,t2,m1,m2,d1,d2;
 wire[AW-1:0] ix=sof?0:x;wire[AV-1:0] iy=sof?0:y;wire[1:0] ib=sof?0:bank;
 wire[DW-1:0] prev=(sbank==0)?q2:(sbank==1)?q0:q1;
 wire[DW-1:0] older=(sbank==0)?q1:(sbank==1)?q2:q0;
 wire[DW-1:0] m=(sy==0)?sd:prev,t=(sy<2)?m:older;
 always @(posedge clk)begin
  if(de_in && !rst)begin
   q0<=b0[ix];q1<=b1[ix];q2<=b2[ix];
   case(ib)0:b0[ix]<=din;1:b1[ix]<=din;2:b2[ix]<=din;endcase
  end
  if(rst)begin
   x<=0;y<=0;bank<=0;pending<=0;de_win<=0;sx<=0;sy<=0;sbank<=0;sd<=0;xo<=0;yo<=0;
   t1<=0;t2<=0;m1<=0;m2<=0;d1<=0;d2<=0;
   w00<=0;w01<=0;w02<=0;w10<=0;w11<=0;w12<=0;w20<=0;w21<=0;w22<=0;
  end else begin
   pending<=de_in;de_win<=pending && !sof;
   if(sof)begin x<=0;y<=0;bank<=0;end
   if(de_in)begin
    sx<=ix;sy<=iy;sbank<=ib;sd<=din;
    if(ix==W-1)begin x<=0;y<=(iy==H-1)?0:iy+1'b1;bank<=(ib==2)?0:ib+1'b1;end
    else x<=ix+1'b1;
   end
   if(pending && !sof)begin
    xo<=sx;yo<=sy;w02<=t;w12<=m;w22<=sd;
    w01<=(sx==0)?t:t1;w00<=(sx==0)?t:(sx==1)?t1:t2;
    w11<=(sx==0)?m:m1;w10<=(sx==0)?m:(sx==1)?m1:m2;
    w21<=(sx==0)?sd:d1;w20<=(sx==0)?sd:(sx==1)?d1:d2;
    t2<=(sx==0)?t:t1;t1<=t;m2<=(sx==0)?m:m1;m1<=m;d2<=(sx==0)?sd:d1;d1<=sd;
   end
  end
 end
 initial begin
  if(W<1 || H<1 || W>(2.0**AW) || H>(2.0**AV))$error("Invalid dimensions");
  if(XOFF!=0 || YOFF!=0)$error("Legacy center offsets unsupported; use causal tags");
 end
endmodule
