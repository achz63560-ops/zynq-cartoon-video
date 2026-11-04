`timescale 1ns/1ps
module quality_test #(parameter FULL=0,TUNE=1);
 localparam W=FULL?640:33,H=FULL?480:19,N=W*H,F=FULL?6:96,TOTAL=N*F;
 reg clk=0;always #10 clk=~clk;
 reg rstn=0,sv=0,su=0,sl=0,mr=0;reg[23:0] sd=0;reg[2:0] mode=0;
 wire sr,mv,mu,ml,fault;wire[23:0] md;wire[2:0] fm;wire[31:0] starts,ends;
 comic_axis #(.W(W),.H(H),.VISUAL_TUNE(TUNE)) dut(clk,rstn,mode,sd,sv,su,sl,sr,md,mv,mu,ml,mr,fm,fault,starts,ends);
 reg[23:0] ins[0:TOTAL-1],exp[0:TOTAL-1];integer rx=0,cyc=0,stalls=0,fd;reg checking=0,held=0;reg[25:0] prior;
 always @(negedge clk)begin cyc=cyc+1;mr=rstn&&cyc%97>32&&cyc%5!=0;end
 always @(posedge clk)if(rstn)begin
  if(fault)$fatal(1,"adapter fault");
  if(held&&(!mv||{mu,ml,md}!==prior))$fatal(1,"stalled data changed");
  held<=mv&&!mr;prior<={mu,ml,md};if(sv&&!sr)stalls=stalls+1;
  if(checking&&mv&&mr)begin
   if(rx>=TOTAL||md!==exp[rx])$fatal(1,"mismatch pixel=%0d got=%h expected=%h",rx,md,exp[rx]);
   if(mu!==(rx%N==0)||ml!==(rx%W==W-1))$fatal(1,"markers");
   if(fm!==(FULL?rx/N:rx/N/16))$fatal(1,"mode changed inside frame");
   if((fm==1||fm==2)&&(md[23:16]!==md[15:8]||md[15:8]!==md[7:0]))$fatal(1,"gray channels unequal");
   if(FULL)$fdisplay(fd,"%06h",md);rx=rx+1;
  end
 end else held<=0;
 task send(input integer p,input[23:0] v);begin
  @(negedge clk);sv=1;sd=v;su=p==0;sl=p%W==W-1;@(posedge clk);while(!sr)@(posedge clk);
 end endtask
 initial begin
  if(FULL)begin $readmemh("vga_in.hex",ins);$readmemh("vga_out.hex",exp);fd=$fopen("rtl_vga_output.hex","w");end
  else begin $readmemh($sformatf("small_%0d_in.hex",TUNE),ins);$readmemh($sformatf("small_%0d_out.hex",TUNE),exp);end
  repeat(5)@(negedge clk);rstn=1;
  for(integer p=0;p<20;p=p+1)send(p,ins[p]);
  @(negedge clk);sv=0;rstn=0;repeat(5)@(negedge clk);rstn=1;checking=1;
  for(integer f=0;f<F;f=f+1)begin
   mode=FULL?f:f/16;
   for(integer p=0;p<N;p=p+1)begin
    if(p==N/2)mode=(FULL?f+1:f/16+1)%6;
    if((FULL||f%16>=8)&&p%7==3)begin @(negedge clk);sv=0;repeat(p%3+1)@(negedge clk);end
    send(p,ins[f*N+p]);
   end
   @(negedge clk);sv=0;wait(rx==(f+1)*N);repeat(3)@(negedge clk);
  end
  repeat(20)@(negedge clk);
  if(stalls<32||starts!=F||ends!=F)$fatal(1,"coverage or count missing");
  if(FULL)$fclose(fd);
  $display("TEST_PASS QUALITY full=%0d tuned=%0d frames=%0d pixels=%0d stalls=%0d reset_abort=1",FULL,TUNE,F,rx,stalls);$finish;
 end
 initial begin #1000000000;$fatal(1,"timeout rx=%0d",rx);end
endmodule
module tb_legacy;quality_test #(.TUNE(0)) t();endmodule
module tb_tuned;quality_test t();endmodule
module tb_quality_vga;quality_test #(.FULL(1)) t();endmodule
