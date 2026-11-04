`timescale 1ns/1ps
module debounced_mode #(parameter integer DEBOUNCE=1000000)(
 input wire clk,resetn,key_n,output reg[2:0] mode,output reg pressed);
 // L14 / PL_KEY0: external 10k pullup to 3.3V, momentary short to GND.
 (* ASYNC_REG="TRUE" *) reg key_meta=1,key_sync=1,key_stable=1;
 reg level,armed;integer count;
 always @(posedge clk)begin
  key_meta<=key_n;key_sync<=key_meta;key_stable<=key_sync;
  if(!resetn)begin mode<=0;pressed<=0;level<=1;armed<=0;count<=0;end
  else begin
   pressed<=0;
   if(key_stable==level)begin
    if(count<DEBOUNCE)count<=count+1;
    if(level && count==DEBOUNCE-1)armed<=1;
   end else if(count!=0)count<=0;
   else begin
    // A separate consecutive mismatch count avoids accepting bounce history.
    level<=key_stable;
   end
   // Stable-low qualification, plus a release-qualified rearm, forbids repeat.
   if(!level && !key_stable && count==DEBOUNCE-1 && armed)begin
    mode<=mode==5?0:mode+1'b1;pressed<=1;armed<=0;
   end
  end
 end
 initial if(DEBOUNCE<2)$error("Debounce must be >=2 cycles");
endmodule
