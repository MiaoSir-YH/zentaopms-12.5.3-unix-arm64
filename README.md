# ZenTao PMS 12.5.3 Unix ARM64 构建

从 [easysoft/zentaopms](https://github.com/easysoft/zentaopms/releases/tag/zentaopms_12.5.3_20210108) 打出两份产物：

| 产物 | 文件 | 说明 |
|------|------|------|
| 源码包 | `ZenTaoPMS.12.5.3.zip` | PHP 源码，架构无关 |
| 一键包 | `ZenTaoPMS.12.5.3.zbox_arm64.tar.gz` | Linux aarch64：Apache 2.4 + PHP 7.4 + MariaDB 10.5 + 禅道 12.5.3 |

GitHub Actions 使用 `ubuntu-24.04-arm` 原生 ARM64 runner。一键包在 Ubuntu 20.04 容器里编译，方便在 glibc 2.31+ 的 ARM64 Linux 上解压即用。

## 一键包安装

必须直接解压到 `/opt`：

```sh
cd /opt
tar xzf ZenTaoPMS.12.5.3.zbox_arm64.tar.gz
/opt/zbox/zbox start
```

- 访问：`http://<IP>/zentao/`
- MySQL：`root` / `123456`
- 改端口：`/opt/zbox/zbox -ap 8080 -mp 3307`

未包含 ionCube（仅 x86）和 xxd 喧喧守护进程（仅 x86）。

## 本地触发

```sh
gh workflow run build.yml
gh run watch
```
