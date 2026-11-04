`timescale 1ns/1ps
// One-frame admission and registered AXIS skid stage. No full-frame buffering.
module axis_frame_gate #(parameter integer W=640,H=480)(
 input wire clk,resetn, // assert only with channel stream reset (or common boot reset)
 input wire arm, // DMA configured/started for a FREE buffer before this pulse
 input wire [23:0] s_data,input wire s_valid,s_user,s_last,output wire s_ready,
 input wire source_done,source_abort,
 output reg [23:0] m_data,output reg m_valid,output reg m_user,m_last,input wire m_ready,
 output reg frame_ok,frame_bad,output reg busy
);
 localparam IDLE=0,SOF=1,ACTIVE=2,TAIL=3,BAD=4;
 reg [2:0] state;reg [31:0] pixels,sent;reg eof_seen;
 wire space=!m_valid||m_ready;
 assign s_ready=(state==SOF||state==ACTIVE)?space:1'b1;
 always @(posedge clk)begin
  if(!resetn)begin state<=IDLE;pixels<=0;sent<=0;eof_seen<=0;
   m_valid<=0;m_data<=0;m_user<=0;m_last<=0;frame_ok<=0;frame_bad<=0;busy<=0;
  end else begin
   frame_ok<=0;frame_bad<=0;
   if(m_valid&&m_ready)begin m_valid<=0;sent<=sent+1;end
   if(arm && state==IDLE && !m_valid)begin
    state<=SOF;pixels<=0;sent<=0;eof_seen<=0;busy<=1;
   end
   if((state==ACTIVE||state==TAIL) && source_done)eof_seen<=1;
   if((state==SOF||state==ACTIVE) && s_valid&&s_ready && (state==ACTIVE||s_user))begin
    // Error priority below prevents publication even if the failing beat was accepted.
    m_valid<=1;m_data<=s_data;m_user<=s_user;m_last<=s_last;
    pixels<=pixels+1;state<=pixels==W*H-1?TAIL:ACTIVE;
    if(s_user!=(pixels==0)||s_last!=(pixels%W==W-1))begin
     state<=BAD;frame_bad<=1;
    end
   end
   if(state==TAIL && (eof_seen||source_done) && sent==W*H && !m_valid)begin
    frame_ok<=1;busy<=0;state<=IDLE;
   end
   if((state==ACTIVE||state==TAIL) && source_abort)begin
    state<=BAD;frame_bad<=1;frame_ok<=0;busy<=1;
   end
   // BAD is sticky until S2MM graceful reset completion. A stalled output beat
   // remains valid and unchanged until accepted or the stream reset is asserted.
  end
 end
endmodule
