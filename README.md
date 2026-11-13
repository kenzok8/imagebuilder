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
  `vmlinux-btf`，也不要把 `vmlinux-btf` 加进 `EXTRA_PACKAGES`。
- ImmortalWrt 24.10 内核没有内置 BTF，必须由脚本从 release 下载同内核版本的
  `vmlinux-btf` IPK 放进本地包目录（见上面「24.10 线注意事项」），
  ImageBuilder 本身无法编译它。

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
- `sdk_line`：SDK 版本线，`25.12-snapshot`（apk）或 `24.10-release`（opkg/ipk），默认 `25.12-snapshot`
- `sdk_release`：`24.10-release` 线使用的具体版本，默认 `24.10.3`
- `imagebuilder_url`：手动指定 ImageBuilder 下载地址；留空则按 `sdk_line` 自动拼
- `preflight`：构建前是否先检查软件包清单，默认 `true`
- `rootfs_partsize`：rootfs 分区大小，默认 `1024` MB
- `install_daede`：是否把 `luci-app-daede` 打进固件，默认 `true`
- `daede_release_tag`：使用哪个 `luci-app-daede` release，默认 `latest`
- `daede_apk_url`：直接指定 APK 下载地址；填写后优先使用这个地址

默认情况下不需要修改这些输入项，直接运行 workflow 即可生成内置
`luci-app-daede` 的 x86/64 固件。

### 24.10 线注意事项

选 `24.10-release` 时，脚本按 ImageBuilder 自带的包管理器自动切到 ipk 流程，
并且必须额外下载 `vmlinux-btf` IPK：

- 24.10 内核没有 `CONFIG_DEBUG_INFO_BTF`，`dae` / `daed` 没有 BTF 无法加载。
- `vmlinux-btf` 的文件名里带内核版本，必须和 ImageBuilder 的内核完全一致。
  脚本会自己探测内核版本再去 release 里找对应的 IPK，找不到就直接失败，
  不会打进版本不符的 BTF。
- 内核 6.6 低于 netkit 需要的 6.7，所以 24.10 上 dae 只能走 veth，
  没有 netkit 的转发性能。

如果目标内核版本在 release 里还没有对应的 `vmlinux-btf`，先去
`kenzok8/openwrt-daede` 的 `Build candidate matrix` 跑一次 SDK 24.10 构建，
把 `btf_kernel_version` 填成目标版本（例如 `6.6.104`），产出对应 IPK 后再回来构建固件。

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
- `sdk_line`: `25.12-snapshot` (apk) or `24.10-release` (opkg/ipk), defaults to
  `25.12-snapshot`
- `sdk_release`: concrete release used by the `24.10-release` line, defaults to
  `24.10.3`
- `imagebuilder_url`: explicit ImageBuilder URL; when empty it is derived from
  `sdk_line`
- `preflight`: run the package manifest check before building, defaults to
  `true`
- `rootfs_partsize`: rootfs partition size, defaults to `1024` MB
- `install_daede`: bake `luci-app-daede` into the image, defaults to `true`
- `daede_release_tag`: `luci-app-daede` release tag to use, defaults to `latest`
- `daede_apk_url`: direct APK download URL; when set, it takes priority

For the normal x86/64 build, leave the inputs unchanged and run the workflow.
The generated image will include `luci-app-daede`.

On the `24.10-release` line the script switches to ipk packaging and additionally
pulls the `vmlinux-btf` IPK whose kernel version matches the ImageBuilder's own
kernel, because 24.10 kernels ship without `CONFIG_DEBUG_INFO_BTF`. A kernel
without a matching `vmlinux-btf` release asset fails the build instead of
shipping a mismatched BTF. Note that 24.10 runs kernel 6.6, so dae falls back to
veth: netkit requires 6.7+.

You can override the daede APK source with environment variables:

- `DAEDE_RELEASE_TAG`: defaults to `latest`
- `DAEDE_ARCH`: defaults to `x86_64`
- `DAEDE_APK_URL`: direct APK URL override
- `INSTALL_DAEDE`: set to `0` to skip baking daede into the image
