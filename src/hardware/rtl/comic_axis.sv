`timescale 1ns/1ps
// Reserve one FIFO credit for EVERY accepted input, including in-flight core
// pixels. The free-running validated core therefore never loses data on stall.
module comic_axis #(parameter W=640,H=480,QBITS=3,BLOCK=8,LOG2B=3,DEPTH=32,VISUAL_TUNE=0)(
 input wire clk,resetn,input wire[2:0] mode_request,
 input wire[23:0] s_data,input wire s_valid,s_user,s_last,output wire s_ready,
 output wire[23:0] m_data,output wire m_valid,m_user,m_last,input wire m_ready,
 output reg[2:0] frame_mode,output reg fault,
 output reg[31:0] frames_started,frames_completed);
 localparam N=W*H,AW=$clog2(DEPTH);
 localparam IDLE=0,ACTIVE=1,DRAIN=2;
 reg[1:0] state;reg[31:0] received,produced,sent;
 reg[AW:0] count,credits;reg[AW-1:0] wp,rp;
 reg[25:0] fifo[0:DEPTH-1];
 wire start=state==IDLE&&s_valid&&s_user&&!fault&&mode_request<6;
 assign s_ready=state==ACTIVE&&received<N&&credits<DEPTH&&!fault;
 wire accept=s_valid&&s_ready;
 wire core_valid;wire[23:0] core_data;
 comic_core #(.W(W),.H(H),.AW(11),.AV(10),.QBITS(QBITS),.BLOCK(BLOCK),.LOG2B(LOG2B),.VISUAL_TUNE(VISUAL_TUNE)) core(
 .clk(clk),.rst(!resetn),.sof(start),.de_in(accept),.vin(s_data),.mode(mode_request),
 .de_out(core_valid),.vout(core_data),.de_s0(),.dbg_smooth(),.dbg_raw(),.dbg_gray(),.dbg_mag(),.dbg_edge());
 assign m_valid=count!=0;assign {m_user,m_last,m_data}=fifo[rp];
 wire pop=m_valid&&m_ready;
 always @(posedge clk)begin
  if(!resetn)begin
   state<=IDLE;received<=0;produced<=0;sent<=0;count<=0;credits<=0;wp<=0;rp<=0;
   frame_mode<=0;fault<=0;frames_started<=0;frames_completed<=0;
  end else begin
   if(state==IDLE&&s_valid&&(!s_user||mode_request>=6))fault<=1;
   if(start)begin state<=ACTIVE;received<=0;produced<=0;sent<=0;frame_mode<=mode_request;frames_started<=frames_started+1;end
   if(accept)begin
    received<=received+1;
    if(s_user!=(received==0)||s_last!=(received%W==W-1))fault<=1;
    if(received==N-1)state<=DRAIN;
   end
   if(core_valid)begin
    if(produced>=N || (count==DEPTH&&!pop) || state==IDLE)fault<=1;
    fifo[wp]<={produced==0,produced%W==W-1,core_data};wp<=wp+1'b1;produced<=produced+1;
   end
   if(pop)begin
    rp<=rp+1'b1;sent<=sent+1;
    if(sent==N-1)begin state<=IDLE;frames_completed<=frames_completed+1;end
   end
   case({core_valid,pop})2'b10:count<=count+1'b1;2'b01:count<=count-1'b1;default:begin end endcase
   case({accept,pop})2'b10:credits<=credits+1'b1;2'b01:credits<=credits-1'b1;default:begin end endcase
  end
 end
 initial if(DEPTH<2 || (1<<AW)!=DEPTH)$error("Comic credit FIFO depth must be power of two");
endmodule
