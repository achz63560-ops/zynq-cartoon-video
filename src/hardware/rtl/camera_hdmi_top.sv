`timescale 1ns/1ps
module camera_hdmi_top(
 inout wire [14:0]DDR_addr,
 inout wire [2:0]DDR_ba,
 inout wire DDR_cas_n,
 inout wire DDR_ck_n,
 inout wire DDR_ck_p,
 inout wire DDR_cke,
 inout wire DDR_cs_n,
 inout wire [3:0]DDR_dm,
 inout wire [31:0]DDR_dq,
 inout wire [3:0]DDR_dqs_n,
 inout wire [3:0]DDR_dqs_p,
 inout wire DDR_odt,
 inout wire DDR_ras_n,
 inout wire DDR_reset_n,
 inout wire DDR_we_n,
 inout wire FIXED_IO_ddr_vrn,
 inout wire FIXED_IO_ddr_vrp,
 inout wire [53:0]FIXED_IO_mio,
 inout wire FIXED_IO_ps_clk,
 inout wire FIXED_IO_ps_porb,
 inout wire FIXED_IO_ps_srstb,
 input wire mode_key_n,
 input wire sys_clk,cam_pclk,cam_vsync,cam_href,cam_xclk_nc,input wire[7:0] cam_data,
 inout wire cam_scl,cam_sda,output wire cam_reset_n,cam_pwdn,
 output wire tmds_clk_p,tmds_clk_n,output wire[2:0] tmds_data_p,tmds_data_n);
 wire sys_clk_i,sys_g,cam_pclk_ibuf,cam_g,pix,serial,clock_locked;
 IBUF sys_pad(.I(sys_clk),.O(sys_clk_i));BUFG sys_global(.I(sys_clk_i),.O(sys_g));
 IBUF pclk_pad(.I(cam_pclk),.O(cam_pclk_ibuf));BUFG pclk_global(.I(cam_pclk_ibuf),.O(cam_g));
 reg[7:0] por=0;always @(posedge sys_g)por<={por[6:0],1'b1};wire resetn=por[7];
 hdmi_clocks clocks(sys_g,!resetn,pix,serial,clock_locked);
 wire pix_reset;
 xpm_cdc_async_rst #(.DEST_SYNC_FF(4),.INIT_SYNC_FF(1),.RST_ACTIVE_HIGH(1)) pixel_reset(
  // MMCMs cannot be locked while POR is asserted; LOCKED already covers POR.
  .src_arst(!clock_locked),.dest_clk(pix),.dest_arst(pix_reset));
 (* IOB="TRUE" *) reg[9:0] pins=0;always @(posedge cam_g)pins<={cam_vsync,cam_href,cam_data};
 (* ASYNC_REG="TRUE" *) reg nc_meta=0,nc_sync=0;always @(posedge sys_g)begin nc_meta<=cam_xclk_nc;nc_sync<=nc_meta;end
 wire system_enable,source_select,arm,video_enable,start_toggle,capture_enable,snapshot_toggle,test_pattern;
 wire[255:0] camera_status,sccb_diag,pipeline_diag;wire[767:0] snapshot;wire[127:0] meta,live_diag,unused_raw_ila;
 camera_dvp_core camera(sys_g,cam_g,resetn,arm,video_enable,start_toggle,capture_enable,snapshot_toggle,
  pins[9],pins[8],pins[7:0],cam_scl,cam_sda,cam_reset_n,cam_pwdn,camera_status,snapshot,meta,live_diag,unused_raw_ila,sccb_diag,test_pattern);
 wire[23:0] front_data;wire front_valid,front_user,front_last,front_ready,front_done,front_abort;
 dvp_axis_bridge #(.FIFO_DEPTH(1024),.READ_STARVE_CYCLES(500000)) frontend(
  .arst_n(resetn),.cam_pclk(cam_g),.process_clk(sys_g),.cam_href(pins[8]),.cam_vsync(pins[9]),.cam_data(pins[7:0]),
  .m_axis_tdata(front_data),.m_axis_tvalid(front_valid),.m_axis_tuser(front_user),.m_axis_tlast(front_last),.m_axis_tready(front_ready),
  .frame_done(front_done),.frame_abort(front_abort));
 wire ps_ready,ready_sys;wire[31:0] ps_control,ps_status;
 xpm_cdc_single #(.SRC_INPUT_REG(0),.DEST_SYNC_FF(4),.INIT_SYNC_FF(1)) ddr_ready_sync(
  .src_clk(sys_g),.src_in(ps_ready),.dest_clk(sys_g),.dest_out(ready_sys));
 wire[23:0] sdata,mdata,rgb;wire svalid,suser,slast,sready,mvalid,muser,mlast,mready;
 wire sreset,mreset;wire[2:0] mkeep;wire de,hs,vs;
 wire[8:0] awaddr,araddr;wire awvalid,wvalid,arvalid,awready,wready,arready,bready,rready,bvalid,rvalid;
 wire[31:0] wd,rd;wire[1:0] bresp,rresp;
 video_dma_pipeline pipeline(
  .clk(sys_g),.pixclk(pix),.rst_n(resetn),.pix_rst_n(!pix_reset),.ddr_ready(ready_sys),.enable(system_enable),.source_select(source_select),
  .camera_ready(camera_status[2]&&!camera_status[3]&&capture_enable),
  .algorithm_mode(algorithm_mode),.mode_diagnostic(mode_diagnostic),
  .camera_data(front_data),.camera_valid(front_valid),.camera_user(front_user),.camera_last(front_last),.camera_done(front_done),.camera_abort(front_abort),.camera_accept(front_ready),
  .s2mm_data(sdata),.s2mm_valid(svalid),.s2mm_user(suser),.s2mm_last(slast),.s2mm_ready(sready),.s2mm_resetn(sreset),
  .mm2s_data(mdata),.mm2s_valid(mvalid),.mm2s_user(muser),.mm2s_last(mlast),.mm2s_ready(mready),
  .rgb(rgb),.de(de),.hsync(hs),.vsync(vs),.diagnostic(pipeline_diag),
  .awaddr(awaddr),.araddr(araddr),.awvalid(awvalid),.wvalid(wvalid),.arvalid(arvalid),.awready(awready),.wready(wready),.arready(arready),
  .wd(wd),.bresp(bresp),.rresp(rresp),.bvalid(bvalid),.rvalid(rvalid),.rd(rd),.bready(bready),.rready(rready));
 backend_wrapper backend(
 .DDR_addr(DDR_addr),
 .DDR_ba(DDR_ba),
 .DDR_cas_n(DDR_cas_n),
 .DDR_ck_n(DDR_ck_n),
 .DDR_ck_p(DDR_ck_p),
 .DDR_cke(DDR_cke),
 .DDR_cs_n(DDR_cs_n),
 .DDR_dm(DDR_dm),
 .DDR_dq(DDR_dq),
 .DDR_dqs_n(DDR_dqs_n),
 .DDR_dqs_p(DDR_dqs_p),
 .DDR_odt(DDR_odt),
 .DDR_ras_n(DDR_ras_n),
 .DDR_reset_n(DDR_reset_n),
 .DDR_we_n(DDR_we_n),
 .FIXED_IO_ddr_vrn(FIXED_IO_ddr_vrn),
 .FIXED_IO_ddr_vrp(FIXED_IO_ddr_vrp),
 .FIXED_IO_mio(FIXED_IO_mio),
 .FIXED_IO_ps_clk(FIXED_IO_ps_clk),
 .FIXED_IO_ps_porb(FIXED_IO_ps_porb),
 .FIXED_IO_ps_srstb(FIXED_IO_ps_srstb),

 .sys_clk(sys_g),.pix_clk(pix),.ps_control(ps_control),.ps_status(ps_status),.s2mm_prmry_reset_out_n(sreset),.mm2s_prmry_reset_out_n(mreset),
 .CAMERA_AXIS_tdata(sdata),.CAMERA_AXIS_tkeep(3'b111),.CAMERA_AXIS_tvalid(svalid),.CAMERA_AXIS_tuser(suser),.CAMERA_AXIS_tlast(slast),.CAMERA_AXIS_tready(sready),
 .DISPLAY_AXIS_tdata(mdata),.DISPLAY_AXIS_tkeep(mkeep),.DISPLAY_AXIS_tvalid(mvalid),.DISPLAY_AXIS_tuser(muser),.DISPLAY_AXIS_tlast(mlast),.DISPLAY_AXIS_tready(mready),
 .VDMA_CTRL_awaddr(awaddr),.VDMA_CTRL_awvalid(awvalid),.VDMA_CTRL_awready(awready),.VDMA_CTRL_wdata(wd),.VDMA_CTRL_wvalid(wvalid),.VDMA_CTRL_wready(wready),
 .VDMA_CTRL_bresp(bresp),.VDMA_CTRL_bvalid(bvalid),.VDMA_CTRL_bready(bready),.VDMA_CTRL_araddr(araddr),.VDMA_CTRL_arvalid(arvalid),.VDMA_CTRL_arready(arready),
 .VDMA_CTRL_rdata(rd),.VDMA_CTRL_rvalid(rvalid),.VDMA_CTRL_rresp(rresp),.VDMA_CTRL_rready(rready));
 wire[9:0] red,green,blue;
 dvi_encoder enc_r(pix,!pix_reset,rgb[23:16],de,2'b00,red);
 dvi_encoder enc_g(pix,!pix_reset,rgb[15:8],de,2'b00,green);
 dvi_encoder enc_b(pix,!pix_reset,rgb[7:0],de,{vs,hs},blue);
 dvi_tx_serial transmitter(pix,serial,!pix_reset,red,green,blue,tmds_clk_p,tmds_clk_n,tmds_data_p,tmds_data_n);
 wire[2:0] algorithm_mode;wire[127:0] mode_diagnostic;
 standalone_control local_control(.clk(sys_g),.resetn(resetn),.key_n(mode_key_n),.clock_locked(clock_locked),.command(ps_control),
 .pipeline(pipeline_diag),.camera(camera_status),.sccb(sccb_diag),.live(live_diag),.meta(meta),.mode_diag(mode_diagnostic),.snapshot(snapshot),
 .front_sof(front_valid&&front_ready&&front_user),.front_done(front_done),.front_abort(front_abort),.response(ps_status),.algorithm_mode(algorithm_mode),
 .ddr_ready(ps_ready),.arm(arm),.video_enable(video_enable),.start_toggle(start_toggle),.capture_enable(capture_enable),
 .system_enable(system_enable),.source_select(source_select),.test_pattern(test_pattern),.snapshot_toggle(snapshot_toggle));
 wire[7:0] vio_unused;wire[2:0] vio_mode_unused;
 wire[255:0] observed_camera={camera_status[255:17],nc_sync,camera_status[15:0]};
 integration_vio vio_r8(.clk(sys_g),.probe_in0(pipeline_diag),.probe_in1(observed_camera),.probe_in2(sccb_diag),
  .probe_in3(live_diag),.probe_in4(meta),.probe_in5(snapshot[511:256]),.probe_in6(snapshot[767:512]),
  .probe_out0(vio_unused[0]),.probe_out1(vio_unused[1]),.probe_out2(vio_unused[2]),.probe_out3(vio_unused[3]),.probe_out4(vio_unused[4]),
  .probe_out5(vio_unused[5]),.probe_out6(vio_unused[6]),.probe_out7(vio_unused[7]),.probe_out8(vio_mode_unused),.probe_in7(mode_diagnostic));
 integration_ila ila_r8(.clk(sys_g),.probe0(pipeline_diag[127:0]));
endmodule
