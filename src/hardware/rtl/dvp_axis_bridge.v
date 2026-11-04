`timescale 1ns/1ps
// Independent PL stream frontend. Does not configure OV5640 or connect DDR/VDMA.
module dvp_axis_bridge #(
 parameter integer W=640,H=480,FIFO_DEPTH=1024,INV_H=0,INV_V=0,LSB_FIRST=0,
 parameter integer CAP_GAP_CYCLES=100000,READ_STARVE_CYCLES=100000
)(
 input wire arst_n,cam_pclk,process_clk,cam_href,cam_vsync,input wire[7:0] cam_data,
 output wire[23:0] m_axis_tdata,output wire m_axis_tvalid,m_axis_tuser,m_axis_tlast,input wire m_axis_tready,
 output wire frame_done,frame_abort,stream_stalled,output wire[3:0] stream_error,
 // These diagnostic buses are in PCLK domain, not safe direct SYS register reads.
 output wire[15:0] captured_good_frames,output wire[7:0] capture_error,
 output wire[31:0] overflow_frames,capture_dropped
);
wire wr_ready,wr_busy,rd_busy;wire[15:0] rgb;wire de,sof,eof,abort_cap;wire[11:0] x;
// The stream's single PCLK reset synchronizer and FIFO reset-busy gate
// release capture together. No parallel reset chains in the same domain.
wire capture_reset_n=wr_ready;
dvp_capture #(.IMG_H(W),.IMG_V(H),.STABLE_FRAMES(0),.INVERT_HREF(INV_H),.INVERT_VSYNC(INV_V),.LSB_FIRST(LSB_FIRST),.GAP_TIMEOUT_CYCLES(CAP_GAP_CYCLES)) capture(
 .cam_pclk(cam_pclk),.rst_n(capture_reset_n),.cam_href(cam_href),.cam_vsync(cam_vsync),.cam_data(cam_data),
 .rgb565(rgb),.de(de),.pixel_x(x),.frame_start(sof),.frame_end(eof),.frame_abort(abort_cap),.frame_cnt(captured_good_frames),.error_flags(capture_error),.dropped_frames(capture_dropped));
video_stream_cdc #(.W(W),.H(H),.FIFO_DEPTH(FIFO_DEPTH),.STARVE_CYCLES(READ_STARVE_CYCLES)) stream(
 .arst_n(arst_n),.wr_clk(cam_pclk),.rd_clk(process_clk),.s_sof(sof),.s_de(de),.s_eol(x==W-1),.s_eof(eof),.s_abort(abort_cap),.s_rgb565(rgb),
 .wr_ready(wr_ready),.overflow_frames(overflow_frames),.m_axis_tdata(m_axis_tdata),.m_axis_tvalid(m_axis_tvalid),.m_axis_tuser(m_axis_tuser),.m_axis_tlast(m_axis_tlast),.m_axis_tready(m_axis_tready),
 .frame_done(frame_done),.frame_abort(frame_abort),.error_code(stream_error),.stream_stalled(stream_stalled),.wr_reset_busy(wr_busy),.rd_reset_busy(rd_busy));
endmodule
