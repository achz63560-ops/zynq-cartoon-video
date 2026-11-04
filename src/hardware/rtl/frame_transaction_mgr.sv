`timescale 1ns/1ps
// Control plane only. DDR pixels are never stored in this module.
// Acks are strong adapter contracts, not raw VDMA IRQ/park-pointer bits.
module frame_transaction_mgr #(
 parameter integer BUFFERS=2, WRITE_TIMEOUT=100000000, RECOVERY_TIMEOUT=200000000
)(
 input wire clk,rst_n,
 input wire boot_quiescent, // BOTH channels reset done, IRQs cleared, output pipeline flushed
 input wire start,
 output reg grant, output reg [1:0] write_buffer, output reg [31:0] write_ticket,
 input wire source_done,source_abort,dma_done,dma_error,
 input wire [31:0] event_ticket,
 output wire s2mm_reset_req,
 input wire s2mm_recovered, // reset bit cleared + halted + stale status/IRQs cleared
 input wire [31:0] recovery_ticket,
 input wire vblank,
 output wire swap_req, output reg [1:0] swap_buffer,output reg [31:0] swap_ticket,
 input wire display_ack,display_boundary,old_reader_drained,
 input wire [31:0] display_ticket,
 output reg display_valid,output reg [1:0] display_buffer,
 output reg published,invalidated, recovery_fault,
 output wire [BUFFERS*3-1:0] states,
 output wire busy
);
 localparam FREE=0, WRITING=1, READY=2, DISPLAYING=3, INVALID=4, PENDING=5;
 reg [2:0] state[0:BUFFERS-1]; reg [31:0] ticket[0:BUFFERS-1];
 reg booted,writing,recovering,pending,got_source,got_dma;
 reg [31:0] sequence_id,write_age,recovery_age;
 integer free_index,ready_index,i;
 assign busy=writing||recovering||!booted;
 assign s2mm_reset_req=recovering;
 assign swap_req=pending;
 genvar g;generate for(g=0;g<BUFFERS;g=g+1)begin:state_export
  assign states[g*3+:3]=state[g];
 end endgenerate
 always @* begin
  free_index=-1;ready_index=-1;
  for(integer k=BUFFERS-1;k>=0;k=k-1)begin
   if(state[k]==FREE) free_index=k;
   // Oldest accepted transaction first. Ticket wrap is excluded by reset epoch contract.
   if(state[k]==READY && (ready_index<0 || ticket[k]<ticket[ready_index]))ready_index=k;
  end
 end
 always @(posedge clk)begin
  if(!rst_n)begin
   for(i=0;i<BUFFERS;i=i+1)begin state[i]<=INVALID;ticket[i]<=0;end
   booted<=0;writing<=0;recovering<=0;pending<=0;got_source<=0;got_dma<=0;
   sequence_id<=0;write_ticket<=0;write_buffer<=0;write_age<=0;recovery_age<=0;
   swap_buffer<=0;swap_ticket<=0;display_valid<=0;display_buffer<=0;
   grant<=0;published<=0;invalidated<=0;recovery_fault<=0;
  end else begin
   grant<=0;published<=0;invalidated<=0;
   if(!booted)begin
    // Never infer that a fabric reset stopped PS DDR transactions.
    if(boot_quiescent)begin
     booted<=1;
     for(i=0;i<BUFFERS;i=i+1)state[i]<=FREE;
    end
   end else begin
    if(recovering)begin
     if(s2mm_recovered && recovery_ticket==write_ticket && !recovery_fault)begin
      recovering<=0;state[write_buffer]<=FREE;recovery_age<=0;
     end else if(recovery_age>=RECOVERY_TIMEOUT-1)recovery_fault<=1;
     else recovery_age<=recovery_age+1;
    end
    if(writing)begin
     if((event_ticket==write_ticket && (source_abort||dma_error)) || write_age>=WRITE_TIMEOUT-1)begin
      state[write_buffer]<=INVALID;writing<=0;recovering<=1;
      invalidated<=1;got_source<=0;got_dma<=0;recovery_age<=0;
     end else begin
      write_age<=write_age+1;
      if(event_ticket==write_ticket)begin
       if(source_done)got_source<=1;
       if(dma_done)got_dma<=1;
       if((got_source||source_done)&&(got_dma||dma_done))begin
        state[write_buffer]<=READY;writing<=0;published<=1;
       end
      end
     end
    end else if(start && !recovering && !recovery_fault && free_index>=0 && sequence_id!=32'hffffffff)begin
     writing<=1;write_buffer<=free_index;write_ticket<=sequence_id+1;
     sequence_id<=sequence_id+1;ticket[free_index]<=sequence_id+1;
     state[free_index]<=WRITING;write_age<=0;got_source<=0;got_dma<=0;grant<=1;
    end
    if(pending)begin
     // No release on a pointer register alone: old queued pixels/reads must be gone.
     if(display_ack && display_boundary && old_reader_drained && display_ticket==swap_ticket)begin
      if(display_valid)state[display_buffer]<=FREE;
      state[swap_buffer]<=DISPLAYING;display_buffer<=swap_buffer;display_valid<=1;pending<=0;
     end
    end else if(vblank && ready_index>=0)begin
     state[ready_index]<=PENDING;pending<=1;swap_buffer<=ready_index;swap_ticket<=ticket[ready_index];
    end
   end
  end
 end
endmodule
