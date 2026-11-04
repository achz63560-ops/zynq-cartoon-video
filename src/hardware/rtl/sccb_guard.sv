`timescale 1ns/1ps
// One physical SCCB master; open-drain SCL/SDA. Fault/abort cleanup resets only
// the controller with SCL held low, then releases SCL. No automatic bus retry.
module sccb_guard #(parameter SYS_HZ=50000000,SCL_HZ=100000)(
 input wire clk,rst_n,allow,exec,rw,input wire[15:0] addr,input wire[7:0] wr,
 input wire scl_pin,sda_pin,output wire[7:0] rd,output reg done,output wire busy,
 output reg[3:0] error,output wire ready,output wire scl_in,sda_in,output wire fault,
 output wire[159:0] diagnostic,output wire scl_drive_low,sda_drive_low);
 localparam Q=SYS_HZ/(4*SCL_HZ),RISE=(SYS_HZ/500000<4)?4:SYS_HZ/500000;
 (* ASYNC_REG="TRUE" *) reg scl_meta,scl_sync,sda_meta,sda_sync;
 always @(posedge clk)begin scl_meta<=scl_pin;scl_sync<=scl_meta;sda_meta<=sda_pin;sda_sync<=sda_meta;end
 assign scl_in=scl_sync;assign sda_in=sda_sync;
 reg[2:0] state;integer timer,rise_count,idle_count;
 reg reset_bus,master_exec,scl_low;wire md,mb,mc,nack;wire[3:0] me;
 reg lat_rw;reg[15:0] lat_addr;reg[7:0] lat_wr;
 wire[63:0] master_diag;wire ack_sample;
 reg[31:0] diag_seq,diag_descriptor,diag_hi,diag_lo;
 reg[4:0] pin_seen,pin_high;reg diag_abort,write_possible;reg[3:0] diag_error;
 assign diagnostic={diag_seq,diag_descriptor,diag_hi,diag_lo,
  {16'd0,pin_seen,pin_high,diag_abort,write_possible,diag_error}};
 assign scl_drive_low=scl_low;
 assign fault=(state==4);assign ready=(state==0)&&idle_count>=2*Q&&!mb;
 assign busy=mb||(state!=0 && state!=4);
 sccb_master #(.CLK_FREQ(SYS_HZ),.SCL_FREQ(SCL_HZ)) master(
 .clk(clk),.rst_n(rst_n&&!reset_bus),.exec(master_exec),.rw(lat_rw),.reg_addr(lat_addr),.wr_data(lat_wr),.rd_data(rd),.done(md),.ack(nack),.scl(mc),.sda_in(sda_pin),.busy(mb),.error_code(me),.diagnostic(master_diag),.ack_sample_pulse(ack_sample),.sda_drive_low(sda_drive_low));
 always @(posedge clk)begin
  if(!rst_n)begin scl_low<=0;end
  else scl_low<=state==1 || state==2 || (!reset_bus && !mc);
 end
 always @(posedge clk)begin
  if(!rst_n)begin
   state<=0;timer<=0;rise_count<=0;idle_count<=0;reset_bus<=0;master_exec<=0;done<=0;error<=0;lat_rw<=0;lat_addr<=0;lat_wr<=0;
   diag_seq<=0;diag_descriptor<=0;diag_hi<=0;diag_lo<=0;pin_seen<=0;pin_high<=0;diag_abort<=0;write_possible<=0;diag_error<=0;
  end
  else begin
   master_exec<=0;done<=0;
   if(scl_sync && sda_sync && !mb)begin if(idle_count<2*Q)idle_count<=idle_count+1;end else idle_count<=0;
   if(mb && mc && !scl_sync)rise_count<=rise_count+1;else rise_count<=0;
   case(state)
    0:begin
     if(exec)begin
      diag_seq<=diag_seq+1;diag_descriptor<={addr,wr,rw,7'd0};
      diag_hi<=0;diag_lo<=0;pin_seen<=0;pin_high<=0;diag_abort<=0;write_possible<=0;diag_error<=0;
      if(allow && !mb)begin lat_rw<=rw;lat_addr<=addr;lat_wr<=wr;state<=5;timer<=0;error<=0;end
      else begin done<=1;error<=4;diag_error<=4;state<=4;end
     end
    end
    5:begin
     if(!allow)begin error<=4;diag_error<=4;diag_abort<=1;state<=1;timer<=0;end
     else if(idle_count>=2*Q)begin master_exec<=1;state<=6;timer<=0;end
     else if(timer>=SYS_HZ/200-1)begin error<=4;diag_error<=4;done<=1;state<=4;end else timer<=timer+1;
    end
    6:begin
     if(ack_sample)begin
      diag_hi<=master_diag[63:32];diag_lo<=master_diag[31:0];
      pin_seen<=pin_seen|(5'b1<<master_diag[21:19]);
      if(scl_sync)pin_high<=pin_high|(5'b1<<master_diag[21:19]);
     end
     if(!allow || rise_count>=RISE)begin
      error<=4;diag_error<=4;diag_abort<=1;state<=1;timer<=0;
      // Preserve the pre-reset transaction trace. Cleanup resets the master,
      // but must never erase the failed/partly applied operation's identity.
      diag_hi<=master_diag[63:32];diag_lo<=master_diag[31:0];
      write_possible<=!lat_rw && (master_diag[3] || master_diag[44:42]==3);
     end else if(md)begin
      done<=1;error<=me;diag_error<=me;state<=(me!=0)?4:0;
      diag_hi<=master_diag[63:32];diag_lo<=master_diag[31:0];
      write_possible<=!lat_rw && (master_diag[3] || master_diag[44:42]==3);
     end
    end
    1:if(timer>=Q-1)begin reset_bus<=1;timer<=0;state<=2;end else timer<=timer+1;
    2:if(timer>=Q-1)begin timer<=0;state<=3;end else timer<=timer+1;
    3:if(timer>=Q-1)begin done<=1;timer<=0;state<=4;end else timer<=timer+1;
    4:begin end
    default:begin state<=4;error<=15;done<=1;end
   endcase
  end
 end
endmodule
