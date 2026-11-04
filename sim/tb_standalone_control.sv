`timescale 1ns/1ps
module tb_standalone_control;
 reg clk=0;always #10 clk=~clk;
 reg resetn=0,key_n=1;reg[31:0] command=0;
 reg[255:0] pipeline=0,camera=0,sccb=0;reg[127:0] live=0,meta=0,mode_diag=0;
 reg[767:0] snapshot=0;reg fsof=0,fdone=0,fabort=0;
 wire[31:0] response;wire[2:0] mode;wire ready,arm,video,start,capture,system_on,source,pattern,snap;
 standalone_control #(.DEBOUNCE(8)) dut(clk,resetn,key_n,1'b1,command,pipeline,camera,sccb,live,meta,mode_diag,snapshot,
 fsof,fdone,fabort,response,mode,ready,arm,video,start,capture,system_on,source,pattern,snap);
 task cycles(input integer n);repeat(n)@(negedge clk);endtask
 task check(input bit ok,input[255:0] reason);if(!ok)$fatal(1,"%s",reason);endtask
 task press;begin
  // < qualification time bounce, then stable press and long hold.
  key_n=0;cycles(2);key_n=1;cycles(2);key_n=0;cycles(24);
 end endtask
 task release_key;begin key_n=1;cycles(2);key_n=0;cycles(2);key_n=1;cycles(24);end endtask
 integer n;reg[2:0] prev;
 initial begin
  // Held at boot is not an intentional mode advance.
  key_n=0;cycles(6);resetn=1;cycles(30);check(mode==0,"held boot key advanced mode");
  release_key();
  for(n=1;n<=12;n=n+1)begin
   prev=mode;press();check(mode==n%6,"mode wrap/bounce failed");
   cycles(100);check(mode==n%6,"long press repeated");
   release_key();check(mode==n%6,"release advanced mode");
  end
  command=32'ha00001ff;cycles(2);
  check({snap,pattern,source,system_on,capture,start,video,arm,ready}==9'h1ff,"PS control decode");
  check(response[31:28]==10 && response[27:24]==11,"sequence or identity");
  camera[127:96]=277;sccb[63:48]=16'h5640;command=32'hb0001000;cycles(2);
  check(response==32'hb1155640,"chip ID transaction status page");
  pipeline[159:128]=811;command=32'hc0002000;cycles(2);check(response==32'hc000032b,"publication page");
  fsof=1;fdone=1;fabort=1;cycles(1);fsof=0;fdone=0;fabort=0;
  command=32'hd000a000;cycles(2);check(response==32'hd0000001,"source SOF count");
  command=32'he000b000;cycles(2);check(response==32'he0000001,"source EOF count");
  command=32'hf000c000;cycles(2);check(response==32'hf0000001,"source abort count");
  resetn=0;cycles(2);check(mode==0,"reset mode not zero");
  $display("TEST_PASS standalone control: 12 debounced/wrapped presses, boot hold, long hold, page echo, ID, counters");$finish;
 end
 initial begin #200000;$fatal(1,"test timeout");end
endmodule
