# Cloudflare 免费代理节点工具

一些用于获取 Cloudflare 免费代理节点的工具。

## WARP 一键工具

### 1、功能说明

本工具可以一键注册 WARP 账户，并自动筛选 WARP MASQUE 优选节点。

主要功能：

- 一键注册 WARP 账户，无需用户自行准备 Cloudflare 账号；
- 自动优选 WARP MASQUE 协议节点；
- 自动生成 Clash/Mihomo 可用的 YAML 配置文件。

> **注：** 脚本全自动运行，无需手动干预。运行完成后，会在当前目录生成 YAML 配置文件，可直接导入支持的 Clash/Mihomo 客户端使用。
### 2、适用平台

#### （1）Windows

- 下载 `script/windows.bat`；
- 新建文件夹，建议使用英文名称，避免中文路径可能带来的兼容性问题；
- 将 `windows.bat` 放入新建的文件夹中；
- 双击运行 `windows.bat`；
- 脚本运行完成后，生成的 `warp-multi.yaml` 位于脚本所在目录，可直接导入 Mihomo / Clash 兼容的客户端使用。

#### （2）macOS

支持 **Intel（x86_64）** 和 **Apple Silicon（arm64）** Mac，包括 M1/M2/M3/M4 以及 MacBook Neo 等设备。

- 下载 `script/Warp_MASQUE_Endpoint_macOS.sh`；
- 新建文件夹，建议使用英文名称，避免中文路径可能带来的兼容性问题；
- 将 `Warp_MASQUE_Endpoint_macOS.sh` 放入新建的文件夹中；
- 右键文件夹，选择“在终端打开”；
- 给脚本赋予执行权限：
  `chmod +x ./Warp_MASQUE_Endpoint_macOS.sh`
- 运行脚本：
  `./Warp_MASQUE_Endpoint_macOS.sh`
- 脚本运行完成后，生成的 `warp-multi.yaml` 位于脚本所在目录，可直接导入 Mihomo / Clash 兼容的客户端使用。

> **注意：** 脚本会自动检测当前 Mac 的 CPU 架构，并下载对应版本的 warpscout，无需手动选择 Intel 或 Apple Silicon 版本。

后续将根据实际使用情况，考虑更新 Linux、Android 等平台的版本。

### 3、视频教程

📺 **YouTube 教程：** [阿尔忒弥斯实验室](https://youtu.be/orRbGeCv9-Y)

### 4、特别鸣谢

本工具的部分功能基于以下开源项目：

- [warpscout](https://github.com/vernette/warpscout)

感谢 `warpscout` 项目的开发者和贡献者。
