`timescale 1ns/1ps
// Fixed raster; one MM2S frame is consumed ONLY in its matching active region.
// A late SOF waits for the next frame, never begins mid-raster. Underflow locks
// the reader and leaves a visible fallback; no unproven buffer retirement.
module hdmi_axis_scan #(parameter W=1280,H=720,HFP=110,HS=40,HBP=220,VFP=5,VS=5,VBP=20)(
 input wire clk,rst_n,input wire[23:0] data,input wire valid,user,last,
 output wire ready,output wire[23:0] rgb,output wire de,hsync,vsync,
 output reg blank_event,first_event,retired_event,output reg fault,
 output reg[31:0] displayed_frames,fallback_frames,output wire[11:0] xpos,ypos);
 localparam HT=W+HFP+HS+HBP,VT=H+VFP+VS+VBP;
 reg[11:0] x,y;reg active;
 wire first=x==0&&y==0;
 wire use_frame=!fault&&(active||(first&&valid&&user));
 assign de=x<W&&y<H;
 assign hsync=x>=W+HFP&&x<W+HFP+HS;
 assign vsync=y>=H+VFP&&y<H+VFP+VS;
 assign ready=de&&use_frame;
 assign xpos=x;assign ypos=y;
 wire[2:0] bars=(x*8)/W;
 reg[23:0] fallback;
 always @*case(bars)0:fallback=24'hffffff;1:fallback=24'hffff00;2:fallback=24'h00ffff;3:fallback=24'h00ff00;
  4:fallback=24'hff00ff;5:fallback=24'hff0000;6:fallback=24'h0000ff;default:fallback=0;endcase
 assign rgb=de?(use_frame?(valid?data:24'hff0000):fallback):24'h0;
 always @(posedge clk)begin
  if(!rst_n)begin x<=0;y<=0;active<=0;fault<=0;blank_event<=0;first_event<=0;retired_event<=0;displayed_frames<=0;fallback_frames<=0;end
  else begin
   blank_event<=0;first_event<=0;retired_event<=0;
   if(x==HT-1)begin x<=0;if(y==VT-1)y<=0;else y<=y+1;end else x<=x+1;
   if(x==0&&y==H)blank_event<=1;
   if(first)begin active<=valid&&user&&!fault;if(!(valid&&user&&!fault))fallback_frames<=fallback_frames+1;end
   if(ready)begin
    if(!valid || user!=first || last!=(x==W-1))begin fault<=1;active<=0;end
    else begin
     if(first)first_event<=1;
     if(x==W-1&&y==H-1)begin retired_event<=1;active<=0;displayed_frames<=displayed_frames+1;end
    end
   end
  end
 end
endmodule
