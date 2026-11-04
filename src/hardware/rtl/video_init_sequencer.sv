`timescale 1ns/1ps
// Single-host command sequencer. Neither ARM nor download alone starts video.
// ROM operations: 0 WRITE, 1 READ_CHECK, 2 WAIT_MS, F END.
module video_init_sequencer #(parameter CLK_HZ=50000000,DEPTH=512,
 parameter ROM_FILE="sequence.mem",BUS_TIMEOUT=250000)(
 input wire clk,rst_n,arm,power_ready,video_enable,start,
 input wire bus_done,bus_busy,input wire[3:0] bus_error,input wire[7:0] bus_rd,
 output reg exec,rw,output reg[15:0] addr,output reg[7:0] wr,
 output reg busy,init_done,failed,output reg[7:0] error,
 output reg[15:0] step_index,output reg[31:0] transactions,rejected,input wire test_pattern);
 reg[63:0] rom[0:DEPTH-1];initial $readmemh(ROM_FILE,rom);
 localparam IDLE=0,FETCH=1,ISSUE=2,WAIT_BUS=3,WAIT_MS=4,FINISHED=5,FAIL=6;
 reg[2:0] state;reg[63:0] cmd;integer timer,limit;reg pattern_latched;
 task fail(input[7:0] code);begin failed<=1;init_done<=0;busy<=0;error<=code;state<=FAIL;end endtask
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin exec<=0;rw<=0;addr<=0;wr<=0;busy<=0;init_done<=0;failed<=0;error<=0;step_index<=0;transactions<=0;rejected<=0;state<=IDLE;cmd<=0;timer<=0;limit<=0;pattern_latched<=0;end
  else begin
   exec<=0;
   if(start && state!=IDLE)rejected<=rejected+1;
   if(busy && (!arm || !video_enable || !power_ready))fail(8'h11);
   else case(state)
    IDLE:if(start)begin
     if(arm && video_enable && power_ready && !bus_busy)begin busy<=1;state<=FETCH;pattern_latched<=test_pattern;end
     else begin rejected<=rejected+1;error<=8'h10;end
    end
    FETCH:begin
     if(step_index>=DEPTH)fail(8'h20);
     else begin cmd<=rom[step_index];state<=ISSUE;end
    end
    ISSUE:begin
     timer<=0;
     case(cmd[63:60])
      // R8 changes ONLY the test-pattern enable register and its matching
      // read-check. PLL/geometry/clock order remain the frozen NACKFIX table.
      // Latched once at accepted start; changing VIO mid-init cannot alter it.
      0,1:if(!bus_busy)begin rw<=(cmd[63:60]==1);addr<=cmd[59:44];wr<= (cmd[59:44]==16'h503d) ? (pattern_latched ? 8'h80 : 8'h00) : cmd[43:36];exec<=1;transactions<=transactions+1;state<=WAIT_BUS;end
          else fail(8'h21);
      2:begin limit<=cmd[27:0]*(CLK_HZ/1000);state<=WAIT_MS;end
      15:begin busy<=0;init_done<=1;error<=0;state<=FINISHED;end
      default:fail(8'h22);
     endcase
    end
    WAIT_BUS:begin
     if(bus_done)begin
      if(bus_error!=0)fail({4'h3,bus_error});
      else if(rw && ((bus_rd & cmd[35:28])!=(wr & cmd[35:28])))fail(8'h40);
      else begin step_index<=step_index+1;state<=FETCH;end
     end else if(timer>=BUS_TIMEOUT-1)fail(8'h50);
     else timer<=timer+1;
    end
    WAIT_MS:if(timer>=limit-1)begin step_index<=step_index+1;state<=FETCH;end else timer<=timer+1;
    FINISHED:begin end
    FAIL:begin end
    default:fail(8'hff);
   endcase
  end
 end
endmodule
