# Shadowsocks-Rust 服务管理脚本

一个轻量、全自动化且高度兼容的 **Shadowsocks-Rust** 服务端一键管理脚本。专门针对多种 Linux 发行版与老旧客户端进行了深度适配与兼容优化。

---

## 🌟 特性亮点

* 🚀 **Musl 静态库支持**：默认优先采用 Musl 静态编译架构包，完美解决 Alpine Linux 等轻量系统缺失 `glibc` 导致程序报错的问题。
* 🛡️ **老旧客户端兼容保障**：安装时后台自动回溯 shadowsocks 官方库 历史版本，逐个下载核验是否包含 `aes-128-gcm` 支持，不满足自动清理并测试上一版本。
* ⚙️ **动态算法提取**：彻底放弃硬编码，自动提取当前版本二进制支持的所有加密算法，并将 `aes-128-gcm` 强制排序在首位推荐。
* 🌐 **IPv4 / IPv6 双栈检测**：内置 3 秒超时智能网络检测，支持生成专属的 IPv4 与 IPv6 格式 `ss://` 导入链接。
* 🔄 **双守护进程适配**：同时兼容 `systemd`（Debian/Ubuntu/CentOS 等）与 `OpenRC`（Alpine Linux 等）服务管理系统。

---

## 🖥️ 支持系统

| 系统架构 | 支持的 Linux 发行版 | 服务守护进程 |
| --- | --- | --- |
| `x86_64` / `amd64` | **Debian** 10+ | Systemd |
| `aarch64` / `arm64` | **Ubuntu** 18.04+ | Systemd |
| `armv7l` / `armhf` | **Alpine Linux** 3.12+ | OpenRC |
| `i386` / `i686` | **CentOS** 7+ / **RHEL** / **Fedora** / **Rocky** / **Alma** | Systemd |
|  | **Arch Linux** | Systemd |

---

## ⚡ 一键安装与运行

使用 `root` 权限登录服务器后，直接复制并执行以下命令：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/BeacherZ/Shadowsocks-Rust/main/ss-rust.sh)

```

---

## 📋 菜单界面概览

```text
╔══════════════════════════════════════════════════════════════╗
║                Shadowsocks-Rust 服务管理脚本                 ║
╠══════════════════════════════════════════════════════════════╣
║  服务状态: ● 运行中 (Shadowsocks-rust-v1.22.0)               ║
╠══════════════════════════════════════════════════════════════╣
║  1. 安装 Shadowsocks-Rust                                    ║
║  2. 更新 Shadowsocks-Rust                                    ║
║  3. 卸载 Shadowsocks-Rust                                    ║
╟──────────────────────────────────────────────────────────────╢
║  4. 启动服务                                                 ║
║  5. 停止服务                                                 ║
║  6. 重启服务                                                 ║
╟──────────────────────────────────────────────────────────────╢
║  7. 查看配置及 SS 链接 (IPv4 / IPv6)                         ║
║  8. 查看运行日志                                             ║
║  0. 退出脚本                                                 ║
╚══════════════════════════════════════════════════════════════╝

```

---

## 📁 文件与目录结构

| 路径 | 说明 |
| --- | --- |
| `/etc/shadowsocks-rust/config.json` | Shadowsocks-Rust 服务配置文件 |
| `/usr/local/bin/ssserver` | 主程序可执行文件 |
| `/etc/systemd/system/shadowsocks-rust.service` | Systemd 服务配置文件 |
| `/etc/init.d/shadowsocks-rust` | OpenRC 服务管理脚本（仅 Alpine 等系统） |

---

## 📄 开源协议

本项目采用 [MIT License](https://www.google.com/search?q=LICENSE) 协议开源。
