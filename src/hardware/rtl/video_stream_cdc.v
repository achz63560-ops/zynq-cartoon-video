`timescale 1ns/1ps
// DVP cannot be backpressured. Event FIFO contains SOF/DATA/EOF/ABORT tokens.
// AXI consumer must commit a frame only on frame_done, discard on frame_abort.
// A previously delivered prefix cannot be retracted without a full-frame store.
module video_stream_cdc #(
 parameter integer W=640,H=480,FIFO_DEPTH=1024,RGB_REPLICATION=1,
 parameter integer STARVE_CYCLES=100000
)(
 input wire arst_n,wr_clk,rd_clk,
 input wire s_sof,s_de,s_eol,s_eof,s_abort,input wire[15:0] s_rgb565,
 output wire wr_ready,output reg[31:0] overflow_frames,source_drops,
 output wire[23:0] m_axis_tdata,output wire m_axis_tvalid,m_axis_tuser,m_axis_tlast,
 input wire m_axis_tready,output reg frame_done,frame_abort,output reg[3:0] error_code,
 output reg stream_stalled,output wire fifo_empty,fifo_full,
 output wire wr_reset_busy,rd_reset_busy
);
localparam [1:0] DATA=0,SOF=1,EOF=2,ABORT=3;
wire wb,rb;
xpm_cdc_async_rst #(.DEST_SYNC_FF(4),.INIT_SYNC_FF(1),.RST_ACTIVE_HIGH(0)) write_reset(
 .src_arst(arst_n),.dest_clk(wr_clk),.dest_arst(wb));
xpm_cdc_async_rst #(.DEST_SYNC_FF(4),.INIT_SYNC_FF(1),.RST_ACTIVE_HIGH(0)) read_reset(
 .src_arst(arst_n),.dest_clk(rd_clk),.dest_arst(rb));
wire fifo_rst=!wb;
wire[18:0] dout;reg[18:0] din;reg push;wire pop,full,empty;
wire overflow,underflow;
reg source_live,pending_abort;
// Synchronous staging keeps asynchronous-reset capture/control registers off
// the BRAM write-enable cone (REQP-1839). Common reset still clears the FIFO.
reg write_gate,q_sof,q_de,q_eol,q_eof,q_abort;reg[15:0] q_pixel;
always @(posedge wr_clk)begin
 if(!wb || wr_reset_busy)begin write_gate<=0;q_sof<=0;q_de<=0;q_eol<=0;q_eof<=0;q_abort<=0;q_pixel<=0;end
 else begin write_gate<=1;q_sof<=s_sof;q_de<=s_de;q_eol<=s_eol;q_eof<=s_eof;q_abort<=s_abort;q_pixel<=s_rgb565;end
end
assign wr_ready=write_gate;
assign fifo_empty=empty;assign fifo_full=full;
always @*begin
 push=0;din=0;
 if(wr_ready && !full)begin
  if(pending_abort || (source_live && q_abort))begin push=1;din={ABORT,17'b0};end
  else if(q_sof)begin push=1;din={SOF,17'b0};end
  else if(source_live && q_de)begin push=1;din={DATA,q_eol,q_pixel};end
  else if(source_live && q_eof)begin push=1;din={EOF,17'b0};end
 end
end
always @(posedge wr_clk)begin
 if(!wb)begin source_live<=0;pending_abort<=0;overflow_frames<=0;source_drops<=0;end
 else if(wr_reset_busy)begin source_live<=0;pending_abort<=0;end
 else if(pending_abort)begin
  if(!full)pending_abort<=0;
  if(q_sof)source_drops<=source_drops+1;
 end else if(source_live && q_abort)begin
  source_live<=0;pending_abort<=full;source_drops<=source_drops+1;
 end else if(q_sof)begin
  if(!full)source_live<=1;
  else begin source_live<=0;pending_abort<=1;overflow_frames<=overflow_frames+1;source_drops<=source_drops+1;end
 end else if(source_live && (q_de || q_eof))begin
  if(full)begin source_live<=0;pending_abort<=1;overflow_frames<=overflow_frames+1;source_drops<=source_drops+1;end
  else if(q_eof)source_live<=0;
 end
end
// Native independent-clock block-RAM FIFO Generator 13.2.5 (C_SELECT_XPM=0).
// XPM 2020.2 assertion failures are retained as failed attempts, not suppressed.
generate if(FIFO_DEPTH==32)begin:small_fifo
 camera_async_fifo_32 fifo(.rst(fifo_rst),.wr_clk(wr_clk),.wr_en(push),.din(din),.full(full),.overflow(overflow),.wr_rst_busy(wr_reset_busy),
 .rd_clk(rd_clk),.rd_en(pop),.dout(dout),.empty(empty),.underflow(underflow),.rd_rst_busy(rd_reset_busy));
end else begin:normal_fifo
 camera_async_fifo_1024 fifo(.rst(fifo_rst),.wr_clk(wr_clk),.wr_en(push),.din(din),.full(full),.overflow(overflow),.wr_rst_busy(wr_reset_busy),
 .rd_clk(rd_clk),.rd_en(pop),.dout(dout),.empty(empty),.underflow(underflow),.rd_rst_busy(rd_reset_busy));
end endgenerate
reg in_frame,first_pixel;
integer x,y,pixels,idle_cycles;
reg read_gate;
always @(posedge rd_clk)if(!rb || rd_reset_busy)read_gate<=0;else read_gate<=1;
wire ready_rd=read_gate;
wire is_data=dout[18:17]==DATA;
assign m_axis_tvalid=ready_rd && !empty && in_frame && is_data;
assign m_axis_tuser=m_axis_tvalid && first_pixel;
assign m_axis_tlast=m_axis_tvalid && dout[16];
wire[4:0] r=dout[15:11],b=dout[4:0];wire[5:0] g=dout[10:5];
assign m_axis_tdata=RGB_REPLICATION?{{r,r[4:2]},{g,g[5:4]},{b,b[4:2]}}:{{r,3'b0},{g,2'b0},{b,3'b0}};
assign pop=ready_rd && !empty && (!is_data || !in_frame || m_axis_tready);
always @(posedge rd_clk)begin
 if(!rb)begin in_frame<=0;first_pixel<=0;x<=0;y<=0;pixels<=0;idle_cycles<=0;frame_done<=0;frame_abort<=0;error_code<=0;stream_stalled<=0;end
 else begin
  frame_done<=0;frame_abort<=0;
  if(rd_reset_busy)begin in_frame<=0;first_pixel<=0;idle_cycles<=0;end
  else if(!empty)begin
   idle_cycles<=0;stream_stalled<=0;
   if(pop)case(dout[18:17])
    SOF:begin
     if(in_frame)begin frame_abort<=1;error_code<=1;end
     in_frame<=1;first_pixel<=1;x<=0;y<=0;pixels<=0;
    end
    ABORT:begin if(in_frame)begin frame_abort<=1;error_code<=2;end in_frame<=0;end
    EOF:begin
     if(in_frame)begin
      if(pixels==W*H && x==0 && y==H)begin frame_done<=1;error_code<=0;end
      else begin frame_abort<=1;error_code<=3;end
     end
     in_frame<=0;
    end
    DATA:if(in_frame)begin
     first_pixel<=0;pixels<=pixels+1;
     if(dout[16]!=(x==W-1) || y>=H)begin frame_abort<=1;error_code<=3;in_frame<=0;end
     if(x==W-1)begin x<=0;y<=y+1;end else x<=x+1;
    end
   endcase
  end else if(STARVE_CYCLES>0)begin
   if(idle_cycles<STARVE_CYCLES)idle_cycles<=idle_cycles+1;
   else begin
    stream_stalled<=1;
    if(in_frame)begin frame_abort<=1;error_code<=4;in_frame<=0;end
   end
  end
 end
end
initial if((FIFO_DEPTH!=32 && FIFO_DEPTH!=1024) || W<1 || H<1)$error("Only generated FIFO depths 32/1024 supported");
endmodule
