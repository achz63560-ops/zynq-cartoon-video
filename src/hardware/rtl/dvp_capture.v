`timescale 1ns/1ps
// All DVP pins are sampled together on rising PCLK. No independent control CDC.
// VSYNC active = vertical blank; falling normalized VSYNC opens a frame.
// HREF active = an uninterrupted row of bytes, MSB first by default.
// Late errors invalidate the entire frame, including its already emitted prefix.
module dvp_capture #(
 parameter [11:0] IMG_H=640,IMG_V=480,parameter XW=12,YW=12,
 parameter [3:0] STABLE_FRAMES=4,parameter INVERT_VSYNC=0,INVERT_HREF=0,
 parameter LSB_FIRST=0,parameter integer GAP_TIMEOUT_CYCLES=100000
)(
 input wire cam_pclk,rst_n,cam_vsync,cam_href,input wire[7:0] cam_data,
 output reg[15:0] rgb565,output reg de,hs,vs,
 output reg[XW-1:0] pixel_x,output reg[YW-1:0] pixel_y,
 output reg frame_stable,output reg[15:0] frame_cnt,
 output reg frame_start,frame_end,frame_abort,line_end,
 output reg[7:0] error_flags,
 output reg[31:0] frame_seen_count,frame_pixels,line_count,dropped_frames,
 output reg[31:0] short_lines,long_lines,odd_lines,sync_errors,stream_timeouts
);
wire v=INVERT_VSYNC?!cam_vsync:cam_vsync;
wire h=INVERT_HREF?!cam_href:cam_href;
reg v_prev,h_prev,open_frame,bad_frame,emit_frame,half_byte;
reg[7:0] first_byte;
integer bytes_in_line,rows,gap_count;
task reject_frame(input[7:0] flags);
 begin
  if(!bad_frame)begin
   frame_abort<=emit_frame;dropped_frames<=dropped_frames+1;error_flags<=error_flags|flags;
   if(flags[0])short_lines<=short_lines+1;
   if(flags[1])long_lines<=long_lines+1;
   if(flags[2])odd_lines<=odd_lines+1;
   if(flags[3] || flags[4])sync_errors<=sync_errors+1;
   if(flags[5])stream_timeouts<=stream_timeouts+1;
  end
  bad_frame<=1;half_byte<=0;
 end
endtask
always @(posedge cam_pclk or negedge rst_n)begin
 if(!rst_n)begin
  v_prev<=0;h_prev<=0;open_frame<=0;bad_frame<=0;emit_frame<=0;half_byte<=0;first_byte<=0;
  bytes_in_line<=0;rows<=0;gap_count<=0;rgb565<=0;de<=0;hs<=0;vs<=0;
  pixel_x<=0;pixel_y<=0;frame_stable<=0;frame_cnt<=0;frame_start<=0;frame_end<=0;frame_abort<=0;line_end<=0;
  frame_seen_count<=0;frame_pixels<=0;line_count<=0;dropped_frames<=0;error_flags<=0;
  short_lines<=0;long_lines<=0;odd_lines<=0;sync_errors<=0;stream_timeouts<=0;
 end else begin
  v_prev<=v;h_prev<=h;de<=0;hs<=0;vs<=0;frame_start<=0;frame_end<=0;frame_abort<=0;line_end<=0;
  if(v && !v_prev)begin
   if(open_frame && !bad_frame)begin
    if(h_prev || h || half_byte || rows!=IMG_V || frame_pixels!=IMG_H*IMG_V)reject_frame(8'h08);
    else begin frame_end<=emit_frame;frame_cnt<=frame_cnt+1'b1;end
   end
   open_frame<=0;half_byte<=0;gap_count<=0;
  end else if(!v && v_prev)begin
   // Require one or more HREF-low clocks after blank before the first byte.
   open_frame<=1;bad_frame<=0;rows<=0;bytes_in_line<=0;half_byte<=0;gap_count<=0;
   frame_pixels<=0;line_count<=0;pixel_x<=0;pixel_y<=0;error_flags<=0;
   frame_seen_count<=frame_seen_count+1;vs<=1;
   emit_frame<=(frame_cnt>=STABLE_FRAMES);frame_stable<=(frame_cnt>=STABLE_FRAMES);
   frame_start<=(frame_cnt>=STABLE_FRAMES);
   if(h)begin bad_frame<=1;error_flags<=8'h10;sync_errors<=sync_errors+1;dropped_frames<=dropped_frames+1;end
  end else if(!v && open_frame && !bad_frame)begin
   if(h)begin
    gap_count<=0;
    if(rows>=IMG_V)reject_frame(8'h08);
    else if(bytes_in_line>=2*IMG_H)reject_frame(8'h02);
    else begin
     bytes_in_line<=bytes_in_line+1;
     half_byte<=!half_byte;
     if(!half_byte)first_byte<=cam_data;
     else begin
      rgb565<=LSB_FIRST?{cam_data,first_byte}:{first_byte,cam_data};
      pixel_x<=(bytes_in_line/2);pixel_y<=rows;
      de<=emit_frame;hs<=emit_frame && bytes_in_line==1;
      frame_pixels<=frame_pixels+1;
     end
    end
   end else if(h_prev)begin
    if(bytes_in_line!=2*IMG_H)reject_frame((bytes_in_line<2*IMG_H?8'h01:8'h02)|(half_byte?8'h04:8'h00));
    else begin rows<=rows+1;line_count<=rows+1;line_end<=emit_frame;end
    bytes_in_line<=0;half_byte<=0;gap_count<=0;
   end else if(GAP_TIMEOUT_CYCLES>0)begin
    if(gap_count>=GAP_TIMEOUT_CYCLES-1)reject_frame(8'h20);
    else gap_count<=gap_count+1;
   end
  end else if(!v && !open_frame && h && !h_prev)begin
   error_flags<=error_flags|8'h10;sync_errors<=sync_errors+1;
  end
 end
end
initial if(IMG_H<1 || IMG_V<1 || IMG_H>=(2.0**XW) || IMG_V>=(2.0**YW))$error("Invalid DVP dimensions");
endmodule
