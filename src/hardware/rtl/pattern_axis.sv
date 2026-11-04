`timescale 1ns/1ps
module pattern_axis #(parameter W=640,H=480)(input wire clk,rst_n,start,
 output wire[23:0] data,output wire valid,user,last,input wire ready,output reg complete);
 reg active;reg[11:0] x,y;
 function automatic[23:0] bar(input integer p);
  case(p)0:bar=24'hffffff;1:bar=24'hffff00;2:bar=24'h00ffff;3:bar=24'h00ff00;
   4:bar=24'hff00ff;5:bar=24'hff0000;6:bar=24'h0000ff;default:bar=0;endcase
 endfunction
 assign data=bar((x*8)/W);assign valid=active;assign user=x==0&&y==0;assign last=x==W-1;
 always @(posedge clk)begin
  if(!rst_n)begin active<=0;x<=0;y<=0;complete<=0;end
  else begin complete<=0;
   if(start&&!active)begin active<=1;x<=0;y<=0;end
   if(valid&&ready)begin
    if(x==W-1)begin x<=0;if(y==H-1)begin active<=0;complete<=1;end else y<=y+1;end
    else x<=x+1;
   end
  end
 end
endmodule
