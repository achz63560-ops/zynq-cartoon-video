`timescale 1ns/1ps
// Autonomous single-frame VDMA adapter. All register accesses are serialized.
// Admission is independent of DMA completion; source+DDR completion both needed.
module vdma_scheduler #(parameter W=640,H=480,CW=1280,CH=720,
 parameter BASE0=32'h10000000,BASE1=32'h10300000,TIMEOUT=25000000,BLANK_BUDGET=20000)(
 input wire clk,rst_n,ddr_ready,enable,source_ready,mode_request,
 input wire frame_ok,frame_bad,input wire blank_event,first_event,retired_event,scan_fault,
 output reg gate_arm,gate_clear,output reg source_mode,
 output wire[5:0] owner_states,output wire[31:0] current_ticket,
 output reg fault,output reg[31:0] last_s2mm,last_mm2s,published_count,display_count,
 output reg command_go,command_write,output reg[8:0] command_addr,output reg[31:0] command_data,
 input wire command_busy,command_done,command_fault,input wire[31:0] command_rdata,
 input wire[2:0] processed_mode,output reg[2:0] display_mode);
 localparam STRIDE=CW*3,OFFSET=((CH-H)/2)*STRIDE+((CW-W)/2)*3;
 localparam IDLE=0,ISSUE=1,WAIT_CMD=2;
 localparam BOOT=0,WRITE_SETUP=1,READ_SETUP=2,WRITE_POLL=3,READ_POLL=4,RECOVER=5;
 reg[1:0] state;reg[2:0] action;reg[4:0] step;
 reg booted,boot_pulse,write_pending,write_active,read_active,read_dma_done,read_output_done;
 reg recovery_active,write_done,write_error,recovered,display_ack;
 reg[31:0] write_addr,read_addr,read_ticket,age,read_age,blank_age;
 reg read_is_pending;reg[1:0] write_buffer_unused;
 reg[2:0] buffer_mode[0:1];reg[1:0] read_buffer_id;
 wire grant,published,invalidated,recovery_fault,manager_busy,reset_req,swap_req,display_valid;
 wire[1:0] write_buffer,swap_buffer,display_buffer;wire[31:0] write_ticket,swap_ticket;
 reg[31:0] recovery_ticket;
 assign current_ticket=write_ticket;
 frame_transaction_mgr #(.WRITE_TIMEOUT(TIMEOUT),.RECOVERY_TIMEOUT(TIMEOUT)) owner(
 .clk(clk),.rst_n(rst_n),.boot_quiescent(boot_pulse),
 .start(booted&&ddr_ready&&enable&&source_ready&&!fault),.grant(grant),.write_buffer(write_buffer),.write_ticket(write_ticket),
 .source_done(frame_ok),.source_abort(frame_bad),.dma_done(write_done),.dma_error(write_error),.event_ticket(write_ticket),
 .s2mm_reset_req(reset_req),.s2mm_recovered(recovered),.recovery_ticket(recovery_ticket),
 .vblank(blank_event),.swap_req(swap_req),.swap_buffer(swap_buffer),.swap_ticket(swap_ticket),
 .display_ack(display_ack),.display_boundary(display_ack),.old_reader_drained(display_ack),.display_ticket(read_ticket),
 .display_valid(display_valid),.display_buffer(display_buffer),.published(published),.invalidated(invalidated),
 .recovery_fault(recovery_fault),.states(owner_states),.busy(manager_busy));
 function automatic[31:0] base(input[1:0] b);base=b==0?BASE0:BASE1;endfunction
 // Commands are stable until accepted by the separate AXI-Lite engine.
 always @*begin
  command_write=1;command_addr=0;command_data=0;
  case(action)
   BOOT:case(step)
    0:begin command_addr='h30;command_data=4;end
    1:begin command_addr=0;command_data=4;end
    2:begin command_write=0;command_addr='h30;end
    3:begin command_write=0;command_addr=0;end
    4:begin command_write=0;command_addr='h34;end
    5:begin command_write=0;command_addr='h04;end
    6:begin command_addr='h34;command_data='hffff;end
    7:begin command_addr='h04;command_data='hffff;end
    8:begin command_write=0;command_addr='h34;end
    default:begin command_write=0;command_addr='h04;end
   endcase
   WRITE_SETUP,READ_SETUP:begin
    case(step)
     0:begin command_addr=action==WRITE_SETUP?'h34:'h04;command_data='hffff;end
     1:begin command_addr='h28;command_data=0;end
     2:begin command_addr=action==WRITE_SETUP?'h30:0;command_data='h00011011;end
     3:begin command_addr=action==WRITE_SETUP?'hac:'h5c;command_data=action==WRITE_SETUP?write_addr+OFFSET:read_addr;end
     4:begin command_addr=action==WRITE_SETUP?'hb0:'h60;command_data=action==WRITE_SETUP?write_addr+OFFSET:read_addr;end
     5:begin command_addr=action==WRITE_SETUP?'ha8:'h58;command_data=STRIDE;end
     6:begin command_addr=action==WRITE_SETUP?'ha4:'h54;command_data=action==WRITE_SETUP?W*3:STRIDE;end
     default:begin command_addr=action==WRITE_SETUP?'ha0:'h50;command_data=action==WRITE_SETUP?H:CH;end
    endcase
   end
   WRITE_POLL:begin command_write=0;command_addr='h34;end
   READ_POLL:begin command_write=0;command_addr='h04;end
   RECOVER:case(step)
    0:begin command_addr='h30;command_data=0;end
    1:begin command_addr='h30;command_data=4;end
    2:begin command_write=0;command_addr='h30;end
    3:begin command_write=0;command_addr='h34;end
    4:begin command_addr='h34;command_data='hffff;end
    default:begin command_write=0;command_addr='h34;end
   endcase
  endcase
 end
 reg poll_turn;
 always @(posedge clk)begin
  if(!rst_n)begin
   state<=IDLE;action<=BOOT;step<=0;booted<=0;boot_pulse<=0;gate_arm<=0;gate_clear<=0;source_mode<=0;fault<=0;
   write_pending<=0;write_active<=0;read_active<=0;read_dma_done<=0;read_output_done<=0;recovery_active<=0;
   write_done<=0;write_error<=0;recovered<=0;display_ack<=0;write_addr<=BASE0;read_addr<=BASE0;read_ticket<=0;
   read_is_pending<=0;recovery_ticket<=0;age<=0;read_age<=0;blank_age<=BLANK_BUDGET;command_go<=0;
   last_s2mm<=0;last_mm2s<=0;published_count<=0;display_count<=0;poll_turn<=0;
   buffer_mode[0]<=0;buffer_mode[1]<=0;read_buffer_id<=0;display_mode<=0;
  end else begin
   command_go<=0;gate_arm<=0;gate_clear<=0;boot_pulse<=0;write_done<=0;write_error<=0;recovered<=0;display_ack<=0;
   if(blank_event)blank_age<=0;else if(blank_age<BLANK_BUDGET)blank_age<=blank_age+1;
   if(published)begin published_count<=published_count+1;buffer_mode[write_buffer]<=processed_mode;end
   if(command_fault||scan_fault||recovery_fault)fault<=1;
   if(grant)begin write_pending<=1;write_addr<=base(write_buffer);source_mode<=mode_request;end
   if(read_active)begin
    read_age<=read_age+1;
    if(read_age>=TIMEOUT-1)fault<=1;
    if(first_event&&read_is_pending)begin
     // Starting this read was permitted only after both old DMA and raster
     // retired. New first pixel is the final ownership-transfer condition.
     display_ack<=1;read_is_pending<=0;display_count<=display_count+1;display_mode<=buffer_mode[read_buffer_id];
    end
    if(retired_event)read_output_done<=1;
    if(read_dma_done&&read_output_done)begin read_active<=0;end
   end
   if(state!=IDLE)begin age<=age+1;if(age>=TIMEOUT-1)fault<=1;end
   if(!fault&&!command_fault&&!scan_fault)case(state)
    IDLE:begin
     age<=0;step<=0;
     if(!booted)begin if(ddr_ready)begin action<=BOOT;state<=ISSUE;end end
     else if(reset_req&&!recovery_active)begin
      action<=RECOVER;state<=ISSUE;recovery_active<=1;recovery_ticket<=write_ticket;write_pending<=0;write_active<=0;
     end else if(!read_active&&blank_age<BLANK_BUDGET&&(swap_req||display_valid))begin
      action<=READ_SETUP;state<=ISSUE;read_addr<=base(swap_req?swap_buffer:display_buffer);
      read_ticket<=swap_req?swap_ticket:0;read_is_pending<=swap_req;read_buffer_id<=swap_req?swap_buffer:display_buffer;
      read_active<=1;read_age<=0;read_dma_done<=0;read_output_done<=0;
      // Consume this blank opportunity once. First pixel may be next frame if late.
      blank_age<=BLANK_BUDGET;
     end else if(write_pending&&!reset_req)begin action<=WRITE_SETUP;state<=ISSUE;write_pending<=0;end
     else if(read_active&&!read_dma_done&&(!write_active||poll_turn))begin action<=READ_POLL;state<=ISSUE;poll_turn<=0;end
     else if(write_active&&!reset_req)begin action<=WRITE_POLL;state<=ISSUE;poll_turn<=1;end
    end
    ISSUE:if(!command_busy)begin command_go<=1;state<=WAIT_CMD;end
    WAIT_CMD:if(command_done)begin
     state<=ISSUE;
     case(action)
      BOOT:begin
       if((step==2||step==3)&&(command_rdata&4)!=0)step<=step;
       else if((step==4||step==5)&&!(command_rdata&1))fault<=1;
       else if((step==8||step==9)&&((command_rdata&32'h0000f9f0)!=0))fault<=1;
       else if(step==9)begin booted<=1;boot_pulse<=1;gate_clear<=1;state<=IDLE;end
       else step<=step+1;
      end
      WRITE_SETUP,READ_SETUP:begin
       if(step==7)begin
        state<=IDLE;
        if(action==WRITE_SETUP)begin gate_arm<=1;write_active<=1;end
       end else step<=step+1;
      end
      WRITE_POLL:begin
       last_s2mm<=command_rdata;state<=IDLE;
       if((command_rdata&32'h000089f0)!=0)begin write_error<=1;write_active<=0;end
       else if((command_rdata&32'h1001)==32'h1001)begin write_done<=1;write_active<=0;end
      end
      READ_POLL:begin
       last_mm2s<=command_rdata;state<=IDLE;
       if((command_rdata&32'h000089f0)!=0)fault<=1;
       else if((command_rdata&32'h1001)==32'h1001)read_dma_done<=1;
      end
      RECOVER:begin
       if(step==2&&(command_rdata&4)!=0)step<=step;
       else if(step==3&&!(command_rdata&1))step<=step;
       else if(step==5)begin
        if((command_rdata&32'h0000f9f0)!=0||!(command_rdata&1))fault<=1;
        else begin recovered<=1;recovery_active<=0;gate_clear<=1;state<=IDLE;end
       end else step<=step+1;
      end
     endcase
    end
   endcase
  end
 end
 initial if((STRIDE%8)!=0||(OFFSET%8)!=0)$error("Unaligned no-DRE geometry");
endmodule
