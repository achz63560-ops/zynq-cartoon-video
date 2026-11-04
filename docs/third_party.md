# 第三方依赖与许可范围

Vivado/Vitis 2020.2 及其 Zynq PS、AXI VDMA、FIFO、VIO、ILA、UNISIM 原语和生成的 FSBL/BSP 由使用者在本机安装或生成，并遵守各自的许可。仓库提供调用这些工具的项目脚本和板级连线约束。

## 完整实现所需的本地板级输入

将已合法取得、具有本地使用权并与 `local_inputs.json` 一致的文件放在 `local_inputs/` 下，保持表中的相对路径。也可以用 `--local-inputs` 指向另一份相同布局的私有输入目录。团队成员可从自己合法持有的封存工程或正式代码包中核对相应文件。未经许可不要转发第三方源码或板级参考数据。

| 路径 | 用途 |
| --- | --- |
| `rtl/dvi_encoder.v` | 单通道 TMDS 编码 |
| `rtl/dvi_tx_serial.v` | 差分 HDMI 发送包装层 |
| `rtl/serializer_10_to_1.v` | OSERDESE2 主从串行器 |
| `reference/ps_board_config.tcl` | 领航者板卡 PS/DDR 参数，供 `ps` BD 单元使用 |
| `reference/sequence.mem` | OV5640 SCCB 初始化 ROM |

厂商参考内容依各权利人许可使用。仓库的 [MIT 许可证](../license) 仅覆盖已获权利人授权并随仓库发布的团队自有贡献。本地输入和本机工具生成的供应商文件各自适用原许可。
