`timescale 1ns/1ps
// Two vendor handshakes: SYS request epoch -> PCLK, atomic held response -> SYS.
// Timeout never retries or accepts a late/stale observation. All old handshakes
// must drain before another explicit request is allowed. XPM has configuration
// INIT state, not a runtime reset; this design's reset is configuration POR only.
module epoch_snapshot #(parameter WIDTH=512,TIMEOUT=500000)(
 input wire sys_clk,pclk,sys_rst_n,p_rst_n,request,invalidate,input wire[31:0] epoch,
 input wire[WIDTH-1:0] src_data,
 output reg[WIDTH-1:0] data_out,output reg[31:0] data_epoch,seq,timeouts,rejected,
 output reg busy,valid,timed_out,output reg stale);
 reg req_send;reg[31:0] req_epoch;wire req_rcv,req_pulse;wire[31:0] pc_epoch;
 xpm_cdc_handshake #(.WIDTH(32),.DEST_EXT_HSK(0),.DEST_SYNC_FF(4),.SRC_SYNC_FF(4),.INIT_SYNC_FF(1),.SIM_ASSERT_CHK(1)) request_cdc(
 .src_clk(sys_clk),.src_in(req_epoch),.src_send(req_send),.src_rcv(req_rcv),.dest_clk(pclk),.dest_out(pc_epoch),.dest_req(req_pulse),.dest_ack(1'b0));
 reg[WIDTH+31:0] held;reg resp_send;reg[1:0] pc_state;wire resp_rcv,resp_pulse;wire[WIDTH+31:0] response;
 xpm_cdc_handshake #(.WIDTH(WIDTH+32),.DEST_EXT_HSK(0),.DEST_SYNC_FF(4),.SRC_SYNC_FF(4),.INIT_SYNC_FF(1),.SIM_ASSERT_CHK(1)) response_cdc(
 .src_clk(pclk),.src_in(held),.src_send(resp_send),.src_rcv(resp_rcv),.dest_clk(sys_clk),.dest_out(response),.dest_req(resp_pulse),.dest_ack(1'b0));
 wire pc_busy_sync;
 xpm_cdc_single #(.SRC_INPUT_REG(1),.DEST_SYNC_FF(4),.INIT_SYNC_FF(1),.SIM_ASSERT_CHK(1)) idle_cdc(
 .src_clk(pclk),.src_in(pc_state!=0),.dest_clk(sys_clk),.dest_out(pc_busy_sync));
 always @(posedge pclk or negedge p_rst_n)begin
  if(!p_rst_n)begin held<=0;resp_send<=0;pc_state<=0;end
  else case(pc_state)
   0:if(req_pulse)begin held<={pc_epoch,src_data};pc_state<=1;end
   1:begin resp_send<=1;pc_state<=2;end
   2:if(resp_rcv)begin resp_send<=0;pc_state<=3;end
   3:if(!resp_rcv)pc_state<=0;
  endcase
 end
 integer age;reg received,saw_busy;
 always @(posedge sys_clk)begin
  if(!sys_rst_n)begin req_send<=0;req_epoch<=0;data_out<=0;data_epoch<=0;seq<=0;timeouts<=0;rejected<=0;busy<=0;valid<=0;timed_out<=0;stale<=0;age<=0;received<=0;saw_busy<=0;end
  else begin
   valid<=0;
   if(req_send && req_rcv)req_send<=0;
   if(request)begin
    if(busy || req_rcv || pc_busy_sync || invalidate)rejected<=rejected+1;
    else begin busy<=1;req_epoch<=epoch;req_send<=1;age<=0;received<=0;saw_busy<=0;timed_out<=0;stale<=0;end
   end
   if(busy)begin
    if(pc_busy_sync)saw_busy<=1;
    if(!received)begin
     if(age>=TIMEOUT-1)begin if(!timed_out)timeouts<=timeouts+1;timed_out<=1;end
     else age<=age+1;
    end
    if(resp_pulse)begin
     received<=1;
     if(!invalidate && !timed_out && age<TIMEOUT-1 && response[WIDTH+31:WIDTH]==epoch && req_epoch==epoch)begin
      data_out<=response[WIDTH-1:0];data_epoch<=epoch;seq<=seq+1;valid<=1;
     end else stale<=1;
    end
    if(received && saw_busy && !pc_busy_sync && !req_rcv && !req_send)busy<=0;
   end
  end
 end
endmodule
