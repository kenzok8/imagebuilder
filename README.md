# imagebuilder

[中文](#中文) | [英文](#english)

## 中文

构建一个 ImmortalWrt x86/64 测试固件，默认包含
[`luci-app-daede`](https://github.com/kenzok8/openwrt-daede) 以及运行
`dae` / `daed` 所需的基础依赖。

### 默认固件

- 版本：ImmortalWrt `25.12-SNAPSHOT`
- 目标：`x86/64`
- Profile：`generic`
- Rootfs 分区：`1024` MB
- ImageBuilder URL：
  `https://downloads.immortalwrt.org/releases/25.12-SNAPSHOT/targets/x86/64/immortalwrt-imagebuilder-25.12-SNAPSHOT-x86-64.Linux-x86_64.tar.zst`
- 快捷链接：
  [`kenzok8/openwrt-daede`](https://github.com/kenzok8/openwrt-daede)

### 默认安装包

工作流默认从
[`kenzok8/openwrt-daede`](https://github.com/kenzok8/openwrt-daede) 的
GitHub Release 下载匹配架构的 `luci-app-daede-*-x86_64.apk`，放入
ImageBuilder 本地包源，然后安装以下软件包：

```text
luci
luci-i18n-base-zh-cn
luci-i18n-package-manager-zh-cn
luci-app-daede
kmod-sched-core
kmod-sched-bpf
kmod-veth
kmod-xdp-sockets-diag
curl
nano
```

ImageBuilder 不会从源码编译 LuCI 应用；这里是把已经编译好的
`luci-app-daede` APK 打进固件。`dae` / `daed` 和内核依赖仍来自所选
ImmortalWrt feed。如果对应 feed 缺少某个依赖，构建会失败。

工作流会在正式构建前运行 `make manifest`，用于更早发现常见 feed 问题：

- snapshot ImageBuilder 和软件包 feed 不同步
- 目标架构当前内核版本缺少某个 `kmod-*` 依赖
- `luci-app-daede` release APK 架构与当前 target 不匹配

关于 BTF：

- ImmortalWrt 25.12 内核默认启用 `CONFIG_DEBUG_INFO_BTF`。`dae` / `daed`
  会在运行时直接读取 `/sys/kernel/btf/vmlinux`，不需要单独安装
  `vmlinux-btf`。
- 不要把 `vmlinux-btf` 加入 `EXTRA_PACKAGES`。该包通常不会在 feed 中发布，
  ImageBuilder 也不能自行编译它。
- 如果要面向缺少内置 BTF 的旧版 OpenWrt，请先通过完整 SDK 构建
  `vmlinux-btf`。

### 首次启动默认值

生成的固件首次启动时会应用以下默认配置：

- LAN IP：`192.168.3.252/24`
- Gateway：`192.168.3.254`
- DNS：`192.168.3.254`、`223.5.5.5`
- SSH 端口：`9167`

仓库和生成的固件不会写入 root 密码。固件保留 OpenWrt 默认的空 root
密码，首次通过 LuCI 或控制台登录后请设置新密码。如需无人值守登录，请通过
私有 workflow 或 secret 注入 SSH 公钥。

### 构建

在 GitHub Actions 手动运行 `Build daede image` workflow。

workflow 会把生成的固件作为 artifact 上传。当 `publish_release` 设置为
`true` 时，也会发布 GitHub Release。

常用输入项：

- `publish_release`：是否发布到 GitHub Release，默认 `false`
- `imagebuilder_url`：ImmortalWrt ImageBuilder 下载地址，默认使用
  `25.12-SNAPSHOT` x86/64
- `preflight`：构建前是否先检查软件包清单，默认 `true`
- `rootfs_partsize`：rootfs 分区大小，默认 `1024` MB
- `install_daede`：是否把 `luci-app-daede` 打进固件，默认 `true`
- `daede_release_tag`：使用哪个 `luci-app-daede` release，默认 `latest`
- `daede_apk_url`：直接指定 APK 下载地址；填写后优先使用这个地址

默认情况下不需要修改这些输入项，直接运行 workflow 即可生成内置
`luci-app-daede` 的 x86/64 固件。

也可通过环境变量覆盖 daede APK 来源：

- `DAEDE_RELEASE_TAG`：默认 `latest`
- `DAEDE_ARCH`：默认 `x86_64`
- `DAEDE_APK_URL`：指定后直接下载该 APK
- `INSTALL_DAEDE`：设为 `0` 可跳过内置 daede

## English

Build an ImmortalWrt x86/64 KVM test image with
[`luci-app-daede`](https://github.com/kenzok8/openwrt-daede) installed by
default, plus the runtime dependencies needed by `dae` / `daed`.

### Default Image

- Version: ImmortalWrt `25.12-SNAPSHOT`
- Target: `x86/64`
- Profile: `generic`
- Rootfs partition: `1024` MB
- ImageBuilder URL:
  `https://downloads.immortalwrt.org/releases/25.12-SNAPSHOT/targets/x86/64/immortalwrt-imagebuilder-25.12-SNAPSHOT-x86-64.Linux-x86_64.tar.zst`
- Shortcut:
  [`kenzok8/openwrt-daede`](https://github.com/kenzok8/openwrt-daede)

### Default Packages

The workflow downloads the matching `luci-app-daede-*-x86_64.apk` from the
[`kenzok8/openwrt-daede`](https://github.com/kenzok8/openwrt-daede) GitHub
Release, places it in ImageBuilder's local package directory, and installs these
packages:

```text
luci
luci-i18n-base-zh-cn
luci-i18n-package-manager-zh-cn
luci-app-daede
kmod-sched-core
kmod-sched-bpf
kmod-veth
kmod-xdp-sockets-diag
curl
nano
```

ImageBuilder does not compile the LuCI app from source. This repository bakes the
prebuilt `luci-app-daede` APK into the image. `dae` / `daed` and kernel
dependencies still come from the selected ImmortalWrt feed. If a dependency is
missing from that feed, the build will fail.

The workflow runs `make manifest` before building the image. This catches common
feed problems earlier, especially:

- snapshot ImageBuilder and package feeds are out of sync
- a required `kmod-*` dependency is missing for the selected target and kernel
- the `luci-app-daede` release APK architecture does not match the selected
  target

About BTF:

- ImmortalWrt 25.12 kernels enable `CONFIG_DEBUG_INFO_BTF` by default. `dae` /
  `daed` read BTF directly from `/sys/kernel/btf/vmlinux` at runtime and do not
  require a separate `vmlinux-btf` package.
- Do not add `vmlinux-btf` to `EXTRA_PACKAGES`. It is usually not published in
  the feed, and ImageBuilder cannot build it.
- If you target an older OpenWrt release whose kernel lacks built-in BTF, build
  `vmlinux-btf` with a full SDK build first.

### First Boot Defaults

The generated image applies these defaults on first boot:

- LAN IP: `192.168.3.252/24`
- Gateway: `192.168.3.254`
- DNS: `192.168.3.254`, `223.5.5.5`
- SSH port: `9167`

No root password is written into this repository or the generated image. The
image keeps the OpenWrt default empty root password, so the first LuCI/console
login should set a new password. For unattended access, inject an SSH public key
using a private workflow/secret-based step.

### Build

Run the `Build daede image` workflow manually from GitHub Actions.

The workflow uploads generated images as an artifact. When `publish_release` is
set to `true`, it also publishes a GitHub release.

Common inputs:

- `publish_release`: publish the generated image to GitHub Releases, defaults to
  `false`
- `imagebuilder_url`: ImmortalWrt ImageBuilder URL, defaults to `25.12-SNAPSHOT`
  x86/64
- `preflight`: run the package manifest check before building, defaults to
  `true`
- `rootfs_partsize`: rootfs partition size, defaults to `1024` MB
- `install_daede`: bake `luci-app-daede` into the image, defaults to `true`
- `daede_release_tag`: `luci-app-daede` release tag to use, defaults to `latest`
- `daede_apk_url`: direct APK download URL; when set, it takes priority

For the normal x86/64 build, leave the inputs unchanged and run the workflow.
The generated image will include `luci-app-daede`.

You can override the daede APK source with environment variables:

- `DAEDE_RELEASE_TAG`: defaults to `latest`
- `DAEDE_ARCH`: defaults to `x86_64`
- `DAEDE_APK_URL`: direct APK URL override
- `INSTALL_DAEDE`: set to `0` to skip baking daede into the image
