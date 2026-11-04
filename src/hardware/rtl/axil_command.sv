`timescale 1ns/1ps
// One outstanding command. Independent AW/W handshakes, no replay on timeout.
module axil_command #(parameter TIMEOUT=500000)(
 input wire clk,rst_n,go,write_cmd,input wire[8:0] address,input wire[31:0] wdata,
 output reg busy,done,fault,output reg[31:0] rdata,
 output reg[8:0] awaddr,araddr,output reg awvalid,wvalid,arvalid,
 input wire awready,wready,arready,output reg[31:0] wd,
 input wire[1:0] bresp,rresp,input wire bvalid,rvalid,input wire[31:0] rd,
 output wire bready,rready);
 reg wr;reg[31:0] age;
 assign bready=busy&&wr&&!awvalid&&!wvalid;
 assign rready=busy&&!wr&&!arvalid;
 always @(posedge clk)begin
  if(!rst_n)begin busy<=0;done<=0;fault<=0;awvalid<=0;wvalid<=0;arvalid<=0;awaddr<=0;araddr<=0;wd<=0;rdata<=0;wr<=0;age<=0;end
  else begin
   done<=0;
   if(go&&!busy&&!fault)begin busy<=1;age<=0;wr<=write_cmd;
    if(write_cmd)begin awaddr<=address;wd<=wdata;awvalid<=1;wvalid<=1;end
    else begin araddr<=address;arvalid<=1;end
   end
   if(busy)begin
    age<=age+1;
    if(awvalid&&awready)awvalid<=0;
    if(wvalid&&wready)wvalid<=0;
    if(arvalid&&arready)arvalid<=0;
    if((bvalid&&bready)||(rvalid&&rready))begin
     busy<=0;done<=1;rdata<=rd;
     if(wr?bresp!=0:rresp!=0)fault<=1;
    end else if(age>=TIMEOUT-1)begin
     // Leave outstanding VALID asserted: the interconnect may still own it.
     // A fault never licenses address reuse or a blind reset/retry.
     fault<=1;
    end
   end
  end
 end
endmodule
