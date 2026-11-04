`timescale 1ns/1ps
module video_dma_pipeline #(parameter W=640,H=480,CW=1280,CH=720,
 parameter HFP=110,HS=40,HBP=220,VFP=5,VS=5,VBP=20,
 parameter BASE0=32'h10000000,BASE1=32'h10300000)(
 input wire clk,pixclk,rst_n,pix_rst_n,ddr_ready,enable,source_select,camera_ready,
 input wire[2:0] algorithm_mode,output wire[127:0] mode_diagnostic,
 input wire[23:0] camera_data,input wire camera_valid,camera_user,camera_last,camera_done,camera_abort,output wire camera_accept,
 output wire[23:0] s2mm_data,output wire s2mm_valid,s2mm_user,s2mm_last,input wire s2mm_ready,s2mm_resetn,
 input wire[23:0] mm2s_data,input wire mm2s_valid,mm2s_user,mm2s_last,output wire mm2s_ready,
 output wire[23:0] rgb,output wire de,hsync,vsync,output wire[255:0] diagnostic,
 output wire[8:0] awaddr,araddr,output wire awvalid,wvalid,arvalid,input wire awready,wready,arready,
 output wire[31:0] wd,input wire[1:0] bresp,rresp,input wire bvalid,rvalid,input wire[31:0] rd,output wire bready,rready);
 wire arm,clear,mode,frame_ok,frame_bad,gate_busy,sched_fault,scan_fault,scan_fault_sys;
 wire bp,fp,rp,bs,fs,rs;wire[31:0] published,switched,sr,rr,ticket;wire[5:0] owners;
 wire cmdgo,cmdwr,cmdbusy,cmddone,cmdfault;wire[8:0] cmdaddr;wire[31:0] cmddata,cmdread;
 wire[23:0] pattern_data;wire pattern_valid,pattern_user,pattern_last,pattern_done,selected_ready;
 wire[23:0] gate_data;wire gate_valid,gate_user,gate_last,algorithm_ready,algorithm_fault;
 wire[2:0] processed_mode,display_mode;wire[31:0] algorithm_started,algorithm_completed;
 wire gate_rst=rst_n&&s2mm_resetn&&!clear;
 assign camera_accept=mode?selected_ready:1'b1;
 pattern_axis #(.W(W),.H(H)) pattern(clk,gate_rst,arm&&!mode,pattern_data,pattern_valid,pattern_user,pattern_last,selected_ready&&!mode,pattern_done);
 axis_frame_gate #(.W(W),.H(H)) gate(clk,gate_rst,arm,
  mode?camera_data:pattern_data,mode?camera_valid:pattern_valid,mode?camera_user:pattern_user,mode?camera_last:pattern_last,
  selected_ready,mode?camera_done:pattern_done,mode?camera_abort:1'b0,
  gate_data,gate_valid,gate_user,gate_last,algorithm_ready,frame_ok,frame_bad,gate_busy);
 comic_axis #(.W(W),.H(H),.VISUAL_TUNE(1)) algorithm(clk,gate_rst,algorithm_mode,
  gate_data,gate_valid,gate_user,gate_last,algorithm_ready,
  s2mm_data,s2mm_valid,s2mm_user,s2mm_last,s2mm_ready,
  processed_mode,algorithm_fault,algorithm_started,algorithm_completed);
 assign mode_diagnostic={32'h4d4f4445,algorithm_started,algorithm_completed,22'd0,algorithm_fault,algorithm_mode,processed_mode,display_mode};
 hdmi_axis_scan #(.W(CW),.H(CH),.HFP(HFP),.HS(HS),.HBP(HBP),.VFP(VFP),.VS(VS),.VBP(VBP)) scan(
  .clk(pixclk),.rst_n(pix_rst_n),.data(mm2s_data),.valid(mm2s_valid),.user(mm2s_user),.last(mm2s_last),.ready(mm2s_ready),
  .rgb(rgb),.de(de),.hsync(hsync),.vsync(vsync),.blank_event(bp),.first_event(fp),.retired_event(rp),.fault(scan_fault),
  .displayed_frames(),.fallback_frames(),.xpos(),.ypos());
 xpm_cdc_pulse #(.DEST_SYNC_FF(4),.INIT_SYNC_FF(1),.REG_OUTPUT(1),.RST_USED(1),.SIM_ASSERT_CHK(1)) bcdc(
  .src_clk(pixclk),.src_rst(!pix_rst_n),.src_pulse(bp),.dest_clk(clk),.dest_rst(!rst_n),.dest_pulse(bs));
 xpm_cdc_pulse #(.DEST_SYNC_FF(4),.INIT_SYNC_FF(1),.REG_OUTPUT(1),.RST_USED(1),.SIM_ASSERT_CHK(1)) fcdc(
  .src_clk(pixclk),.src_rst(!pix_rst_n),.src_pulse(fp),.dest_clk(clk),.dest_rst(!rst_n),.dest_pulse(fs));
 xpm_cdc_pulse #(.DEST_SYNC_FF(4),.INIT_SYNC_FF(1),.REG_OUTPUT(1),.RST_USED(1),.SIM_ASSERT_CHK(1)) rcdc(
  .src_clk(pixclk),.src_rst(!pix_rst_n),.src_pulse(rp),.dest_clk(clk),.dest_rst(!rst_n),.dest_pulse(rs));
 xpm_cdc_single #(.SRC_INPUT_REG(0),.DEST_SYNC_FF(4),.INIT_SYNC_FF(1)) ecdc(
  .src_clk(pixclk),.src_in(scan_fault),.dest_clk(clk),.dest_out(scan_fault_sys));
 vdma_scheduler #(.W(W),.H(H),.CW(CW),.CH(CH),.BASE0(BASE0),.BASE1(BASE1)) scheduler(
  .clk(clk),.rst_n(rst_n),.ddr_ready(ddr_ready),.enable(enable),.source_ready(!source_select||camera_ready),.mode_request(source_select),
  .frame_ok(frame_ok),.frame_bad(frame_bad),.blank_event(bs),.first_event(fs),.retired_event(rs),.scan_fault(scan_fault_sys||algorithm_fault),
  .gate_arm(arm),.gate_clear(clear),.source_mode(mode),.owner_states(owners),.current_ticket(ticket),
  .fault(sched_fault),.last_s2mm(sr),.last_mm2s(rr),.published_count(published),.display_count(switched),
  .command_go(cmdgo),.command_write(cmdwr),.command_addr(cmdaddr),.command_data(cmddata),.command_busy(cmdbusy),.command_done(cmddone),.command_fault(cmdfault),.command_rdata(cmdread),
  .processed_mode(processed_mode),.display_mode(display_mode));
 axil_command control(clk,rst_n,cmdgo,cmdwr,cmdaddr,cmddata,cmdbusy,cmddone,cmdfault,cmdread,
  awaddr,araddr,awvalid,wvalid,arvalid,awready,wready,arready,wd,bresp,rresp,bvalid,rvalid,rd,bready,rready);
 reg[31:0] retired_count,heartbeat;
 always @(posedge clk)begin
  if(!rst_n)begin retired_count<=0;heartbeat<=0;end
  else begin heartbeat<=heartbeat+1;if(rs)retired_count<=retired_count+1;end
 end
 assign diagnostic={32'h51554c31,32'h26110301,heartbeat,published,switched,retired_count,
  sr[15:0],rr[15:0],ticket[15:0],4'd0,ddr_ready,enable,owners,source_select,mode,sched_fault,scan_fault_sys};
endmodule
