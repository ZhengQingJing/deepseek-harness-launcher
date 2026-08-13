# deepseek-harness Launcher

一个 macOS 原生小工具：双击即可启动 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（`dsh`）的 Web UI，并自动在默认浏览器打开。

图标是 DeepSeek 鲸鱼 logo 的黑色版本。

## 功能

- **一键启动** — 双击 App，自动检查端口 → 启动 `dsh web` → 等待就绪 → 打开浏览器。
- **自动发现 Node.js** — 依次查找 `PATH`、Homebrew、nvm 等常见安装位置，无需任何配置。
- **智能启动** — 检测到本地有 `~/Documents/deepseek-harness` 源码构建则秒开；否则通过 `npx @deepseek-ai/dsh web` 自动下载启动，无需手动 clone 或构建。
- **实时日志** — 窗口内滚动显示启动日志，失败时可一键打开日志文件排查。
- **Universal** — 同时支持 Apple Silicon (arm64) 和 Intel (x86_64)。

## 快速开始

### 方式一：直接下载（推荐）

1. 到 [Releases](../../releases) 下载最新的 `DS-H-Launcher-*.zip`。
2. 解压，把 `DS-H Launcher.app` 拖进 `应用程序`（Applications）。
3. 双击打开。

> **首次打开提示**：因为 App 未经过 Apple 付费开发者签名，macOS 可能拦截。
> 首次双击后如提示"无法验证开发者"，请**右键点击 App → 打开 → 再点打开**即可（只需一次）。

### 方式二：从源码构建

```bash
git clone https://github.com/ZhengQingJing/deepseek-harness-launcher.git
cd deepseek-harness-launcher
./build.sh
# 产物在 dist/ 目录
```

## 前置要求

- macOS 13.0 或更高版本。
- [Node.js](https://nodejs.org/) 22.19 或更高版本（首次启动时会自动检测，未安装则引导到官网下载）。

## 工作原理

App 内部执行以下流程：

```
双击 App
  → 检测 3080 端口是否有服务在响应
  → 有：直接打开浏览器
  → 无：清理残留进程 → 启动服务（本地源码优先，否则 npx）→ 轮询等待就绪 → 打开浏览器
```

日志文件位置：`~/Library/Logs/DS-H-Launcher/dsh-web.log`

## 生成图标

```bash
pip install pillow
python3 assets/make-icon.py
```

脚本会下载 DeepSeek 官方头像，处理成黑色鲸鱼并生成 `AppIcon.icns`。

## 项目结构

```
deepseek-harness-launcher/
├── src/main.swift      # App 源码（含内嵌启动脚本）
├── assets/             # 图标资源与生成脚本
├── Info.plist          # app bundle 元信息
├── build.sh            # 一键构建 + 签名 + 打包
└── LICENSE
```

## 免责声明

本工具是 DeepSeek Harness 的第三方启动器，与 DeepSeek AI 无隶属关系。"DeepSeek" 及相关 logo 商标归其所有者所有。图标基于官方 logo 修改，仅用于标识本工具。
