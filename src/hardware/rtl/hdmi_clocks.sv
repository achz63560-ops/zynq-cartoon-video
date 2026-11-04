`timescale 1ns/1ps
// 50 * 37.125 / 2 / 12.5 = 74.25 MHz. Cascaded second MMCM produces
// related CLKDIV=74.25 and DDR serializer CLK=371.25 from legal 742.5 MHz VCO.
module hdmi_clocks(input wire sysclk,rst,output wire pixclk,serialclk,locked);
 wire fb0,fb0g,c0,c0g,l0,fb1,fb1g,c1,c5,l1;
 MMCME2_BASE #(.CLKIN1_PERIOD(20.0),.DIVCLK_DIVIDE(2),.CLKFBOUT_MULT_F(37.125),.CLKOUT0_DIVIDE_F(12.5)) m0(
 .CLKIN1(sysclk),.CLKFBIN(fb0g),.CLKFBOUT(fb0),.CLKOUT0(c0),.LOCKED(l0),.RST(rst),.PWRDWN(1'b0));
 BUFG bf0(.I(fb0),.O(fb0g));BUFG bc0(.I(c0),.O(c0g));
 MMCME2_BASE #(.CLKIN1_PERIOD(13.468013),.DIVCLK_DIVIDE(1),.CLKFBOUT_MULT_F(10.0),.CLKOUT0_DIVIDE_F(10.0),.CLKOUT1_DIVIDE(2)) m1(
 .CLKIN1(c0g),.CLKFBIN(fb1g),.CLKFBOUT(fb1),.CLKOUT0(c1),.CLKOUT1(c5),.LOCKED(l1),.RST(rst||!l0),.PWRDWN(1'b0));
 BUFG bf1(.I(fb1),.O(fb1g));BUFG bp(.I(c1),.O(pixclk));BUFG bs(.I(c5),.O(serialclk));
 assign locked=l0&&l1;
endmodule
