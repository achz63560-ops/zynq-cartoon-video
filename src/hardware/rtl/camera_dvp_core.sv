`timescale 1ns/1ps
module camera_dvp_core #(
 parameter SYS_HZ=50000000,W=640,H=480,INV_V=0,INV_H=0,LSB=0,
 parameter ROM_FILE="sequence.mem",PCLK_LIMIT=SYS_HZ/100,FRAME_LIMIT=SYS_HZ*2,
 parameter SNAP_TIMEOUT=SYS_HZ/100,SETTLE_MS=20,HOLD_MS=2,BOOT_MS=25
)(input wire sys_clk,pclk,sys_rst_n,
 input wire arm,video_enable,start_toggle,capture_enable,snapshot_toggle,
 input wire vsync,href,input wire[7:0] data,inout wire cam_scl,cam_sda,
 output reg cam_reset_n,cam_pwdn,
 output wire[255:0] status,output wire[767:0] snapshot_data,output wire[127:0] snapshot_meta,live_diag,
 output wire[127:0] ila_data,output wire[255:0] sccb_diagnostic,input wire test_pattern);
 initial begin cam_reset_n=0;cam_pwdn=1;end
 wire p_rst,stream_reset;
 xpm_cdc_async_rst #(.DEST_SYNC_FF(3),.INIT_SYNC_FF(1),.RST_ACTIVE_HIGH(1)) pclk_por(
  .src_arst(!sys_rst_n),.dest_clk(pclk),.dest_arst(p_rst));
 wire p_rst_n=!p_rst;
 reg armed_once,abandoned;reg[2:0] power_state;integer power_timer;
 wire power_ready=power_state==4;
 reg prev_start,prev_snap;
 wire init_start=start_toggle!=prev_start;
 wire snap_request=snapshot_toggle!=prev_snap;
 always @(posedge sys_clk)begin
  if(!sys_rst_n)begin armed_once<=0;abandoned<=0;power_state<=0;power_timer<=0;cam_reset_n<=0;cam_pwdn<=1;prev_start<=0;prev_snap<=0;end
  else begin
   prev_start<=start_toggle;prev_snap<=snapshot_toggle;
   if(arm)armed_once<=1;
   if(armed_once && !arm)abandoned<=1;
   if(!arm || abandoned)begin power_state<=0;power_timer<=0;cam_reset_n<=0;cam_pwdn<=1;end
   else case(power_state)
    0:begin power_state<=1;power_timer<=0;end
    1:if(power_timer>=SYS_HZ/1000*SETTLE_MS-1)begin power_timer<=0;cam_pwdn<=0;power_state<=2;end else power_timer<=power_timer+1;
    2:if(power_timer>=SYS_HZ/1000*HOLD_MS-1)begin power_timer<=0;cam_reset_n<=1;power_state<=3;end else power_timer<=power_timer+1;
    3:if(power_timer>=SYS_HZ/1000*BOOT_MS-1)begin power_timer<=0;power_state<=4;end else power_timer<=power_timer+1;
    4:begin end
    default:begin power_state<=0;cam_reset_n<=0;cam_pwdn<=1;end
   endcase
  end
 end
 wire exec,rw,bd,bb,brdy,bfault,scl_in,sda_in;wire[15:0] addr,step;wire[7:0] wr,rd,init_error;wire[3:0] bus_error;
 wire init_busy,init_done,init_failed;wire[31:0] transactions,init_rejected;
 wire[159:0] bus_diagnostic;
 wire scl_pin,sda_pin,scl_drive_low,sda_drive_low;
 // Exactly ONE explicit open-drain IOBUF per physical SCCB pin. No nested
 // inferred tristates or duplicated input buffers; input synchronizers stay.
 IOBUF sccb_scl_buffer(.I(1'b0),.T(!scl_drive_low),.O(scl_pin),.IO(cam_scl));
 IOBUF sccb_sda_buffer(.I(1'b0),.T(!sda_drive_low),.O(sda_pin),.IO(cam_sda));
 sccb_guard #(.SYS_HZ(SYS_HZ)) guard(sys_clk,sys_rst_n,arm&&video_enable&&!abandoned&&!init_failed,exec,rw,addr,wr,scl_pin,sda_pin,rd,bd,bb,bus_error,brdy,scl_in,sda_in,bfault,bus_diagnostic,scl_drive_low,sda_drive_low);
 video_init_sequencer #(.CLK_HZ(SYS_HZ),.DEPTH(280),.ROM_FILE(ROM_FILE),.BUS_TIMEOUT(SYS_HZ/100)) init_seq(
 sys_clk,sys_rst_n,arm&&!abandoned,power_ready,video_enable,init_start,
 bd,bb,bus_error,rd,exec,rw,addr,wr,init_busy,init_done,init_failed,init_error,step,transactions,init_rejected,test_pattern);
 reg[7:0] id_high,id_low,last_read;reg high_valid,low_valid,read_valid;reg[15:0] last_read_addr;
 always @(posedge sys_clk)begin
  if(!sys_rst_n)begin id_high<=0;id_low<=0;last_read<=0;high_valid<=0;low_valid<=0;read_valid<=0;last_read_addr<=0;end
  else if(bd && rw)begin
   last_read<=rd;last_read_addr<=addr;read_valid<=(bus_error==0);
   if(bus_error==0 && addr==16'h300a)begin id_high<=rd;high_valid<=1;end
   if(bus_error==0 && addr==16'h300b)begin id_low<=rd;low_valid<=1;end
  end
 end
 assign sccb_diagnostic={bus_diagnostic,
  {addr,rd,rw,bd,bb,exec,brdy,bfault,cam_reset_n,cam_pwdn},
  {id_high,id_low,last_read,3'd0,(high_valid&&low_valid&&{id_high,id_low}==16'h5640),read_valid,high_valid,low_valid,1'b0},
  {last_read_addr,step}};
 wire expected=arm&&power_ready&&init_done&&!init_failed&&!bfault&&!abandoned&&capture_enable;
 reg[4:0] pclk_div;reg frame_toggle;
 wire[15:0] pixel;wire de,sof,eof,ab;wire[11:0] x,y;wire[7:0] flags;wire[31:0] cp,last_crc;wire[767:0] src_payload;
 always @(posedge pclk or negedge p_rst_n)begin
  if(!p_rst_n)begin pclk_div<=0;frame_toggle<=0;end
  else begin pclk_div<=pclk_div+1;if(eof)frame_toggle<=~frame_toggle;end
 end
 wire tick_sync,frame_sync;
 xpm_cdc_single #(.SRC_INPUT_REG(0),.DEST_SYNC_FF(4),.INIT_SYNC_FF(1),.SIM_ASSERT_CHK(1)) tick_cdc(.src_clk(pclk),.src_in(pclk_div[4]),.dest_clk(sys_clk),.dest_out(tick_sync));
 xpm_cdc_single #(.SRC_INPUT_REG(0),.DEST_SYNC_FF(4),.INIT_SYNC_FF(1),.SIM_ASSERT_CHK(1)) frame_cdc(.src_clk(pclk),.src_in(frame_toggle),.dest_clk(sys_clk),.dest_out(frame_sync));
 reg prev_tick,prev_frame,pclk_stopped,frame_stopped,prev_fs,prev_run;
 integer tick_age,frame_age,recovery;reg[31:0] pc_stops,fr_stops,epoch,heartbeat;
 wire run_intent=expected&&!pclk_stopped&&(recovery==0);
 reg run_allowed=0;
 wire epoch_changing=(prev_run!=run_allowed)||(run_intent!=run_allowed);
 // Count BOTH transitions of PCLK/32: one event per 16 PCLK cycles.
 // A 1ms SYS window gives 16kHz quantization, plus SYS oscillator error.
 reg[31:0] freq_edges,freq_age,pclk_hz,freq_windows;
 always @(posedge sys_clk)begin
  if(!sys_rst_n)begin freq_edges<=0;freq_age<=0;pclk_hz<=0;freq_windows<=0;end
  else if(freq_age>=SYS_HZ/1000-1)begin
   pclk_hz<=(freq_edges+(tick_sync!=prev_tick))*16000;
   freq_edges<=0;freq_age<=0;freq_windows<=freq_windows+1;
  end else begin freq_age<=freq_age+1;if(tick_sync!=prev_tick)freq_edges<=freq_edges+1;end
 end
 assign live_diag={pclk_hz,freq_windows,pc_stops,fr_stops};
 always @(posedge sys_clk)begin
  if(!sys_rst_n)begin run_allowed<=0;prev_tick<=0;prev_frame<=0;pclk_stopped<=0;frame_stopped<=0;prev_fs<=0;prev_run<=0;tick_age<=0;frame_age<=0;recovery<=0;pc_stops<=0;fr_stops<=0;epoch<=0;heartbeat<=0;end
  else begin
   run_allowed<=run_intent;
   heartbeat<=heartbeat+1;prev_tick<=tick_sync;prev_frame<=frame_sync;prev_fs<=frame_stopped;prev_run<=run_allowed;
   if(prev_run!=run_allowed)epoch<=epoch+1;
   if(recovery!=0)recovery<=recovery-1;
   if(frame_stopped&&!prev_fs)recovery<=64;
   if(!expected)begin tick_age<=0;frame_age<=0;pclk_stopped<=0;frame_stopped<=0;end
   else begin
    if(tick_sync!=prev_tick)begin tick_age<=0;pclk_stopped<=0;end
    else if(tick_age>=PCLK_LIMIT-1)begin pclk_stopped<=1;if(!pclk_stopped)pc_stops<=pc_stops+1;end else tick_age<=tick_age+1;
    if(frame_sync!=prev_frame)begin frame_age<=0;frame_stopped<=0;end
    else if(frame_age>=FRAME_LIMIT-1)begin frame_stopped<=1;if(!frame_stopped)fr_stops<=fr_stops+1;end else frame_age<=frame_age+1;
   end
  end
 end
 // Single registered reset source: no binary-decode/LUT fan-in at the CDC.
 // run_allowed INIT=0 and SYS POR both hold this asserted without any PCLK.
 xpm_cdc_async_rst #(.DEST_SYNC_FF(3),.INIT_SYNC_FF(1),.RST_ACTIVE_HIGH(1)) capture_release(.src_arst(!run_allowed),.dest_clk(pclk),.dest_arst(stream_reset));
 wire stream_run=!stream_reset;
 capture_stats #(.W(W),.H(H),.INV_V(INV_V),.INV_H(INV_H),.LSB(LSB)) stats(
 pclk,p_rst_n,stream_run,vsync,href,data,pixel,de,sof,eof,ab,x,y,flags,cp,last_crc,src_payload);
 wire[31:0] snap_epoch,snap_seq,snap_timeouts,snap_rejected;wire snap_busy,snap_valid,snap_timeout,snap_stale;
 epoch_snapshot #(.WIDTH(768),.TIMEOUT(SNAP_TIMEOUT)) snapshots(sys_clk,pclk,sys_rst_n,p_rst_n,snap_request,epoch_changing,epoch,src_payload,snapshot_data,snap_epoch,snap_seq,snap_timeouts,snap_rejected,snap_busy,snap_valid,snap_timeout,snap_stale);
 assign snapshot_meta={snap_seq,snap_epoch,snap_timeouts,snap_rejected};
 wire snapshot_current=(snap_seq!=0)&&(snap_epoch==epoch)&&!epoch_changing&&!snap_timeout&&!snap_stale&&!snap_busy;
 wire[31:0] controls={3'd0,init_error,bus_error,1'b0,abandoned,bfault,brdy,sda_in,scl_in,snap_stale,snap_timeout,snapshot_current,snap_busy,frame_stopped,pclk_stopped,expected,init_failed,init_done,init_busy,power_ready};
 assign status={32'h44565038,32'h26102808,heartbeat,epoch,transactions,{step,init_rejected[15:0]},{pc_stops[15:0],fr_stops[15:0]},controls};
 assign ila_data={last_crc,cp,pixel,x,y,{vsync,href,data},flags,sof,eof,ab,de,stream_run,p_rst_n};
endmodule
