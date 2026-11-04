`timescale 1ns/1ps
// Global source reset is independent of stream reset. Last-good data survives
// a stopped PCLK, capture disable, or resynchronization of the input parser.
module capture_stats #(parameter W=640,H=480,GAP=100000,INV_V=0,INV_H=0,LSB=0)(
 input wire pclk,rst_n,stream_run,vsync,href,input wire[7:0] data,
 output wire[15:0] pixel,output wire de,sof,eof,ab,
 output wire[11:0] x,y,output wire[7:0] flags,
 output wire[31:0] live_pixels,last_crc,output wire[767:0] payload);
 wire[31:0] cp,cl,unused_seen,unused_drop,sl,ll,ol,se,ge;
 wire[15:0] fc;wire stable,hs,vs,le;
 dvp_capture #(.IMG_H(W),.IMG_V(H),.STABLE_FRAMES(0),.GAP_TIMEOUT_CYCLES(GAP),.INVERT_VSYNC(INV_V),.INVERT_HREF(INV_H),.LSB_FIRST(LSB)) capture(
 .cam_pclk(pclk),.rst_n(stream_run),.cam_vsync(vsync),.cam_href(href),.cam_data(data),.rgb565(pixel),.de(de),.hs(hs),.vs(vs),.pixel_x(x),.pixel_y(y),.frame_stable(stable),.frame_cnt(fc),
 .frame_start(sof),.frame_end(eof),.frame_abort(ab),.line_end(le),.error_flags(flags),.frame_seen_count(unused_seen),.frame_pixels(cp),.line_count(cl),.dropped_frames(unused_drop),.short_lines(sl),.long_lines(ll),.odd_lines(ol),.sync_errors(se),.stream_timeouts(ge));
 reg[31:0] good,bad,crc,last_n,last_b,last_l,shorts,longs,odds,syncs,gaps,stops,started,epoch,good_epoch,last_flags;
 reg[31:0] running_crc,emitted;reg active,run_prev;
 reg[255:0] working_samples,last_samples;integer s;
 assign live_pixels=cp;assign last_crc=crc;
 // Sixteen RGB565 samples at first-row segment centres. Stored only on a
 // validated EOF, atomically with that frame's CRC and geometry.
 assign payload={last_samples,good,bad,crc,last_n,last_b,last_l,shorts,longs,odds,syncs,gaps,stops,started,epoch,good_epoch,last_flags};
 function automatic[31:0] crc_byte(input[31:0] seed,input[7:0] b);
 reg[31:0] q;integer k;
 begin q=seed^{24'd0,b};for(k=0;k<8;k=k+1)q=q[0]?((q>>1)^32'hedb88320):(q>>1);crc_byte=q;end
 endfunction
 always @(posedge pclk or negedge rst_n)begin
  if(!rst_n)begin
   good<=0;bad<=0;crc<=0;last_n<=0;last_b<=0;last_l<=0;shorts<=0;longs<=0;odds<=0;syncs<=0;gaps<=0;stops<=0;started<=0;epoch<=0;good_epoch<=0;last_flags<=0;
   working_samples<=0;last_samples<=0;running_crc<=32'hffffffff;emitted<=0;active<=0;run_prev<=0;
  end else begin
   run_prev<=stream_run;
   if(stream_run && !run_prev)epoch<=epoch+1;
   if(!stream_run)begin
    if(active)begin bad<=bad+1;stops<=stops+1;last_flags<=32'h40;end
    working_samples<=0;active<=0;emitted<=0;running_crc<=32'hffffffff;
   end else begin
    if(sof)begin working_samples<=0;active<=1;emitted<=0;running_crc<=32'hffffffff;started<=started+1;end
    if(de && active)begin emitted<=emitted+1;running_crc<=crc_byte(crc_byte(running_crc,pixel[15:8]),pixel[7:0]);end
    if(de && active && y==0)begin
     for(s=0;s<16;s=s+1)if(x==((2*s+1)*W)/32)working_samples[s*16+:16]<=pixel;
    end
    if(ab)begin
     bad<=bad+1;active<=0;last_flags<={24'd0,flags};
     if(flags[0])shorts<=shorts+1;if(flags[1])longs<=longs+1;if(flags[2])odds<=odds+1;
     if(flags[3]||flags[4])syncs<=syncs+1;if(flags[5])gaps<=gaps+1;
    end
    if(eof)begin
     active<=0;
     if(active && emitted==W*H && cp==W*H && cl==H && flags==0)begin
      last_samples<=working_samples;good<=good+1;crc<=~running_crc;last_n<=emitted;last_b<=emitted*2;last_l<=cl;good_epoch<=epoch;
     end else begin bad<=bad+1;last_flags<=32'h80;end
    end
   end
  end
 end
endmodule
