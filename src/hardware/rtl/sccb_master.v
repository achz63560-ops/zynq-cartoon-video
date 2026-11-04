`timescale 1ns/1ps
// Four phases: setup while LOW, rise, sample HIGH, fall without changing SDA.
// Open-drain SDA. Read: address-write/STOP/START/address-read/data/master NACK.
// Registered push-pull SCL: clock stretching/multi-master are not supported.
// done: one cycle. ack: aggregate failure flag, sticky until next command.
// error_code: 0 OK, 1 NACK, 2 timeout, 3 bus not free at STOP.
module sccb_master #(
 parameter integer CLK_FREQ=50_000_000,SCL_FREQ=250_000,
 parameter [6:0] SLAVE_ADDR=7'h3c,
 parameter integer TIMEOUT_CYCLES=(CLK_FREQ/SCL_FREQ)*128
)(
 input wire clk,rst_n,exec,rw,input wire[15:0] reg_addr,input wire[7:0] wr_data,
 output reg[7:0] rd_data,output reg done,ack,output reg scl,input wire sda_in,
 output reg busy,output reg[3:0] error_code,
 output wire[63:0] diagnostic,output reg ack_sample_pulse,output wire sda_drive_low
);
localparam integer DIV=CLK_FREQ/(4*SCL_FREQ);
localparam [3:0] IDLE=0,BUS_WAIT=1,START=2,TX=3,ACK=4,RX=5,NACK=6,STOP=7;
(* ASYNC_REG="TRUE" *) reg reset_a,reset_b;
always @(posedge clk or negedge rst_n)
 if(!rst_n)begin reset_a<=0;reset_b<=0;end else begin reset_a<=1;reset_b<=reset_a;end
wire reset_n=reset_b;
(* ASYNC_REG="TRUE" *) reg sda_a,sda_b;
reg drive_low;
assign sda_drive_low=drive_low;
always @(posedge clk or negedge reset_n)
 if(!reset_n)begin sda_a<=1;sda_b<=1;end else begin sda_a<=sda_in;sda_b<=sda_a;end
reg[3:0] state;
reg[2:0] phase;
reg[2:0] bit_index,byte_index;
reg[7:0] shift,read_shift,data_latched;
reg[15:0] addr_latched;
reg read_latched,restart_read,timed_out;
integer divider,watchdog;
// ACK stages: 0 slave-W, 1 register-high, 2 register-low, 3 write-data,
// 4 slave-R after the read restart. A master's read NACK is NOT an error.
// Trace records sampled/known/low masks and the FIRST failed ACK, not a retry.
reg[31:0] ack_trace;
assign diagnostic={{8'd0,error_code,state,phase,byte_index,bit_index,
 read_latched,restart_read,timed_out,1'b0,sda_b,drive_low,scl},ack_trace};
// Bit35 is reserved zero: never fan out the first metastability-catching
// synchronizer stage sda_a into debug logic. Only sda_b is observed.
always @(posedge clk or negedge reset_n)begin
 if(!reset_n)begin
  state<=IDLE;phase<=0;divider<=0;watchdog<=0;busy<=0;done<=0;ack<=0;error_code<=0;
  scl<=1;drive_low<=0;rd_data<=0;shift<=0;read_shift<=0;bit_index<=7;byte_index<=0;
  addr_latched<=0;data_latched<=0;read_latched<=0;restart_read<=0;timed_out<=0;
  ack_trace<=0;ack_sample_pulse<=0;
 end else begin
  done<=0;ack_sample_pulse<=0;
  if(state==IDLE)begin
   divider<=0;scl<=1;drive_low<=0;busy<=0;
   if(exec)begin
    busy<=1;ack<=0;error_code<=0;rd_data<=0;watchdog<=0;timed_out<=0;phase<=0;
    addr_latched<=reg_addr;data_latched<=wr_data;read_latched<=rw;
    byte_index<=0;shift<={SLAVE_ADDR,1'b0};bit_index<=7;restart_read<=0;state<=BUS_WAIT;
    ack_trace<=0;
   end
  end else if(!timed_out && watchdog>=TIMEOUT_CYCLES-1)begin
   error_code<=2;ack<=1;timed_out<=1;restart_read<=0;state<=STOP;phase<=0;divider<=0;
   ack_trace[31:29]<=phase;ack_trace[28:25]<=state;
  end else begin
   watchdog<=watchdog+1;
   if(divider==DIV-1)begin
    divider<=0;
    case(state)
     BUS_WAIT:begin
      scl<=1;drive_low<=0;
      if(sda_b===1'b1)begin state<=START;phase<=0;end
     end
     START:case(phase)
      0:begin scl<=1;drive_low<=0;phase<=1;end
      1:begin drive_low<=1;phase<=2;end
      2:begin scl<=0;phase<=0;state<=TX;end
     endcase
     TX:case(phase)
      0:begin drive_low<=!shift[bit_index];phase<=1;end
      1:begin scl<=1;phase<=2;end
      2:phase<=3;
      3:begin scl<=0;phase<=0;if(bit_index==0)state<=ACK;else bit_index<=bit_index-1'b1;end
     endcase
     ACK:case(phase)
      0:begin drive_low<=0;phase<=1;end
      1:begin scl<=1;phase<=2;end
      2:begin
       ack_sample_pulse<=1;
       ack_trace[4:0]<=ack_trace[4:0]|(5'b1<<byte_index);
       if(sda_b===1'b0)ack_trace[9:5]<=ack_trace[9:5]|(5'b1<<byte_index);
       if(sda_b===1'b0 || sda_b===1'b1)ack_trace[14:10]<=ack_trace[14:10]|(5'b1<<byte_index);
       ack_trace[21:19]<=byte_index;ack_trace[22]<=(sda_b===1'b1);
       ack_trace[23]<=(sda_b===1'b0 || sda_b===1'b1);ack_trace[24]<=scl;
       if(sda_b!==1'b0 && !ack_trace[18])begin
        ack_trace[18]<=1;ack_trace[17:15]<=byte_index;
        ack_trace[31:29]<=phase;ack_trace[28:25]<=state;
       end
       if(sda_b!==1'b0)begin ack<=1;error_code<=1;end
       phase<=3;
      end
      3:begin
       scl<=0;phase<=0;bit_index<=7;
       if(error_code!=0)begin restart_read<=0;state<=STOP;end
       else case(byte_index)
        0:begin byte_index<=1;shift<=addr_latched[15:8];state<=TX;end
        1:begin byte_index<=2;shift<=addr_latched[7:0];state<=TX;end
        2:if(read_latched)begin restart_read<=1;state<=STOP;end
          else begin byte_index<=3;shift<=data_latched;state<=TX;end
        3:begin restart_read<=0;state<=STOP;end
        4:begin read_shift<=0;state<=RX;end
        default:begin error_code<=3;ack<=1;state<=STOP;end
       endcase
      end
     endcase
     RX:case(phase)
      0:begin drive_low<=0;phase<=1;end
      1:begin scl<=1;phase<=2;end
      2:begin read_shift<={read_shift[6:0],sda_b};phase<=3;end
      3:begin scl<=0;phase<=0;if(bit_index==0)begin rd_data<=read_shift;state<=NACK;end else bit_index<=bit_index-1'b1;end
     endcase
     NACK:case(phase)
      0:begin drive_low<=0;phase<=1;end
      1:begin scl<=1;phase<=2;end
      2:phase<=3;
      3:begin scl<=0;phase<=0;restart_read<=0;state<=STOP;end
     endcase
     STOP:case(phase)
      // Timeout may enter from SCL HIGH. First lower SCL, then change SDA
      // one complete quarter later, keeping the abort path free of data glitches.
      0:begin scl<=0;phase<=1;end
      1:begin drive_low<=1;phase<=2;end
      2:begin scl<=1;phase<=3;end
      3:begin drive_low<=0;phase<=4;end
      4:begin
       phase<=0;
       if(sda_b!==1'b1)begin error_code<=(error_code==0)?3:error_code;ack<=1;restart_read<=0;busy<=0;done<=1;state<=IDLE;end
       else if(restart_read)begin byte_index<=4;shift<={SLAVE_ADDR,1'b1};bit_index<=7;restart_read<=0;state<=BUS_WAIT;end
       else begin busy<=0;done<=1;state<=IDLE;end
      end
     endcase
     default:begin state<=STOP;phase<=0;error_code<=3;ack<=1;end
    endcase
   end else divider<=divider+1;
  end
 end
end
initial begin
 if(DIV<2 || SCL_FREQ<=0 || TIMEOUT_CYCLES<8)$error("Invalid SCCB timing parameters; quarter period must be >=2 clk cycles");
end
endmodule
