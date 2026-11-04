`timescale 1ns/1ps
// AXI GPIO itself is clocked by this SYS clock. Its AXI interconnect performs
// the vendor 100MHz PS -> 50MHz SYS transaction crossing, not a 2FF word bus.
module standalone_control #(parameter DEBOUNCE=1000000)(
 input wire clk,resetn,key_n,clock_locked,input wire[31:0] command,
 input wire[255:0] pipeline,camera,sccb,input wire[127:0] live,meta,mode_diag,
 input wire[767:0] snapshot,input wire front_sof,front_done,front_abort,
 output wire[31:0] response,output wire[2:0] algorithm_mode,
 output wire ddr_ready,arm,video_enable,start_toggle,capture_enable,system_enable,source_select,test_pattern,snapshot_toggle);
 wire pressed;
 debounced_mode #(.DEBOUNCE(DEBOUNCE)) key(clk,resetn,key_n,algorithm_mode,pressed);
 assign {snapshot_toggle,test_pattern,source_select,system_enable,capture_enable,start_toggle,video_enable,arm,ddr_ready}=command[8:0];
 reg[27:0] payload;reg[27:0] sof_count,done_count,abort_count;
 always @(posedge clk)begin
  if(!resetn)begin sof_count<=0;done_count<=0;abort_count<=0;end
  else begin
   if(front_sof)sof_count<=sof_count+1;
   if(front_done)done_count<=done_count+1;
   if(front_abort)abort_count<=abort_count+1;
  end
 end
 always @*begin
  payload=0;
  case(command[15:12])
   0:begin
    payload[27:24]=4'hb;
    payload[21:19]=algorithm_mode;payload[18:16]=mode_diag[2:0];
    payload[15]=camera[9];payload[14]=camera[10];payload[13]=camera[8];payload[12]=camera[7];
    payload[11]=mode_diag[9];payload[10]=pipeline[0];payload[9]=pipeline[1];payload[8]=pipeline[11];
    payload[7]=clock_locked;payload[6]=camera[15];payload[5]=camera[14];
    payload[4]=camera[4];payload[3:0]=camera[3:0];
   end
   1:payload={camera[107:96],sccb[63:48]}; // 12-bit transaction count + chip ID
   2:payload=pipeline[155:128];
   3:payload=pipeline[123:96];
   4:payload=live[123:96];
   5:payload=mode_diag[59:32];
   6:payload={12'd0,camera[28:17],4'd0};
   7:payload=snapshot[763:736];
   8:payload=meta[123:96];
   9:payload={22'd0,pipeline[9:4]};
   10:payload=sof_count;
   11:payload=done_count;
   12:payload=abort_count;
   13:payload=pipeline[187:160];
   14:payload={12'd0,pipeline[63:48]};
   15:payload={12'd0,pipeline[47:32]};
  endcase
 end
 // Application checks a sequence echo after every atomic GPIO command.
 assign response={command[31:28],payload};
endmodule
