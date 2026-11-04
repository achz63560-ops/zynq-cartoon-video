# Zynq 实时漫画视频

系统用 OV5640 采集 640×480 RGB565 视频，在 Zynq-7000 的 PL 侧执行像素流水处理，经 AXI VDMA 在 PS DDR 双缓冲，最后经 HDMI 输出 1280×720、60 Hz 光栅。640×480 图像居中显示。HDMI 刷新率与摄像头新画面更新率独立，实机新版未定量测量后者。

## 六种模式

| 编号 | 模式 | 像素处理 |
| --- | --- | --- |
| 0 | 原始图像 | 保留采集颜色 |
| 1 | 八阶灰度漫画 | 灰度量化并叠加黑色轮廓 |
| 2 | 黑白线稿 | 使用边缘阈值输出黑线与白底 |
| 3 | 颜色量化 | 降低各颜色通道的等级数 |
| 4 | 8×8 马赛克 | 使用每块左上像素填充 |
| 5 | 彩色漫画 | 将颜色量化与黑色轮廓叠加 |

## 硬件与工具

- 正点原子领航者 ZYNQ-7020，器件 `xc7z020clg400-2`，板载 PS DDR。
- ATK-MC5640 V1.2 摄像头，DVP 数据及 SCCB 控制；HDMI 显示器、FAT32 TF 卡。
- 上电由 TF 卡启动。短按 `PL_KEY0`（L14）循环切换，模式在帧边界生效。
- Windows、Vivado 与 Vitis **2020.2**，包含 Zynq-7000 器件、HSI/XSCT、ARM GCC 和 Bootgen。Python 3.10+ 用于检查及构建入口，生成仿真数据另需 NumPy、Pillow。

## 目录

| 路径 | 内容 |
| --- | --- |
| `src/hardware/rtl`、`constraints` | PL 采集、算法、流控、缓存调度与显示 RTL；引脚及时序 XDC |
| `src/hardware/scripts` | PS/BD、VDMA、FIFO 和调试 IP 创建、实现及导出 Tcl |
| `src/software/app` | Cortex-A9 裸机 C、启动汇编和链接脚本 |
| `sim`、`data` | Testbench、独立整数参考、合成测试图及向量哈希 |
| `tools`、`skill` | 校验、复现入口及可复用验证步骤 |

## 复现

先运行 `python tools/verify.py`。下列命令默认检查输入并打印计划，添加 `--execute` 才调用工具，输出位于 `reproduced/<时间>/<阶段>`。`VIVADO_2020_2` 和 `VITIS_2020_2` 分别指向本机对应版本的安装根目录，可用 `--vivado`、`--vitis` 覆盖。

1. 查阅 [本地板级输入](docs/third_party.md)，准备与封存版本相符且有权使用的五个输入文件。完整实现依赖这些本地输入；每项的路径及 SHA-256 见 `docs/local_inputs.json`。
2. 执行 `python tools/reproduce.py implement --local-inputs local_inputs`，检查实施报告和生成的 `routed.dcp`。
3. 执行 `python tools/reproduce.py export --checkpoint <routed.dcp>`，通过导出检查后取得同一实现的 `.bit`、`.xsa`。
4. 执行 `python tools/reproduce.py app` 编译裸机程序，再执行 `python tools/reproduce.py fsbl --xsa <导出的.xsa>`，由本机 HSI 生成 FSBL/BSP。
5. 执行 `python tools/reproduce.py boot --fsbl <fsbl.elf> --bit <导出的.bit> --app-elf <standalone.elf>`，检查 Bootgen 解析结果。将生成的 `BOOT.BIN` 放入 FAT32 TF 卡根目录并按板卡手册设置 SD 启动后，可进行板上验证。

离线算法仿真无需板级输入。安装 `numpy`、`Pillow` 后运行 `python sim/generate_quality_vectors.py --output reproduced/vectors`，随后运行 `python tools/reproduce.py sim --vectors reproduced/vectors`。仿真入口核对六个向量的哈希。仓库另有实体按键/脱机控制 Testbench 和裸机状态机的 C 测试。

该源码版本以已验收工程为基线整理。复现入口和输入在发布整理时进行静态核对；上板、时序及画质结论以对应版本的实机与封存报告为准。DVP 输入窗口属于约束模型，外部 DVP/HDMI 时序仍需正式签核。

## 许可与来源

团队实际拥有并获准公开的代码及相关文档采用 [MIT 许可证](license)，版权署名为 2026 帧有此理团队。完整硬件构建还需自行合法取得五个指定的板级输入，获取范围与哈希见 [第三方依赖说明](docs/third_party.md)。从公开快照单独克隆可准备算法仿真，生成同版启动镜像需要上述本地输入。

请查阅 [第三方依赖与许可范围](docs/third_party.md)。团队成员负责硬件搭建、需求与实机验收。相关开发协作记录随比赛材料独立保存。
