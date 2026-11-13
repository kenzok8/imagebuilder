#!/usr/bin/env bash
set -euo pipefail

# SDK 版本线：25.12-snapshot（apk）或 24.10-release（ipk）
SDK_LINE="${SDK_LINE:-25.12-snapshot}"
SDK_RELEASE="${SDK_RELEASE:-24.10.3}"

case "$SDK_LINE" in
  24.10*)
    IB_RELEASE="$SDK_RELEASE"
    ;;
  *)
    IB_RELEASE="25.12-SNAPSHOT"
    ;;
esac

VERSION="${VERSION:-$IB_RELEASE}"
TARGET="${TARGET:-x86/64}"
PROFILE="${PROFILE:-generic}"
IMAGEBUILDER_URL="${IMAGEBUILDER_URL:-https://downloads.immortalwrt.org/releases/$IB_RELEASE/targets/x86/64/immortalwrt-imagebuilder-$IB_RELEASE-x86-64.Linux-x86_64.tar.zst}"
EXTRA_IMAGE_NAME="${EXTRA_IMAGE_NAME:-daede}"
OUT_DIR="${OUT_DIR:-$PWD/out}"
PREFLIGHT="${PREFLIGHT:-1}"
ROOTFS_PARTSIZE="${ROOTFS_PARTSIZE:-1024}"
INSTALL_DAEDE="${INSTALL_DAEDE:-1}"
DAEDE_REPO="${DAEDE_REPO:-kenzok8/openwrt-daede}"
DAEDE_RELEASE_TAG="${DAEDE_RELEASE_TAG:-latest}"
DAEDE_ARCH="${DAEDE_ARCH:-x86_64}"
DAEDE_APK_URL="${DAEDE_APK_URL:-}"

EXTRA_PACKAGES="${EXTRA_PACKAGES:-luci luci-i18n-base-zh-cn luci-i18n-package-manager-zh-cn luci-app-daede kmod-sched-core kmod-sched-bpf kmod-veth kmod-xdp-sockets-diag curl nano}"

WORK_DIR="${WORK_DIR:-$PWD/work}"
IB_ARCHIVE="$WORK_DIR/imagebuilder.tar.zst"

mkdir -p "$WORK_DIR" "$OUT_DIR"

# 在 release 里按前缀/后缀找资产，找不到就报错并列出候选
resolve_release_asset() {
  local prefix="$1" suffix="$2" label="$3"

  local release_api
  if [ "$DAEDE_RELEASE_TAG" = "latest" ]; then
    release_api="https://api.github.com/repos/$DAEDE_REPO/releases/latest"
  else
    release_api="https://api.github.com/repos/$DAEDE_REPO/releases/tags/$DAEDE_RELEASE_TAG"
  fi

  python3 - "$release_api" "$prefix" "$suffix" "$label" <<'PY'
import json
import os
import sys
import urllib.request

release_api, prefix, suffix, label = sys.argv[1:5]
request = urllib.request.Request(
    release_api,
    headers={
        "Accept": "application/vnd.github+json",
        "User-Agent": "kenzok8-imagebuilder",
    },
)
token = os.environ.get("GITHUB_TOKEN")
if token:
    request.add_header("Authorization", f"Bearer {token}")

with urllib.request.urlopen(request, timeout=30) as response:
    release = json.load(response)

names = [asset.get("name", "") for asset in release.get("assets", [])]
matches = [
    asset.get("browser_download_url") or asset.get("url")
    for asset, name in zip(release.get("assets", []), names)
    if name.startswith(prefix) and name.endswith(suffix)
]

if not matches:
    tag = release.get("tag_name", release_api)
    candidates = sorted({n for n in names if n.startswith(prefix.split("_")[0])})
    detail = "\n  " + "\n  ".join(candidates[:12]) if candidates else ""
    raise SystemExit(f"{label} not found in {tag} (prefix={prefix}, suffix={suffix}){detail}")

print(matches[0])
PY
}

# ImageBuilder 自带 apk 工具就是 apk 线（25.12），否则是 opkg 线（<=24.10）
detect_pkg_format() {
  local ib="$1"
  if find "$ib/staging_dir/host/bin" -maxdepth 1 -name '*apk*' 2>/dev/null | grep -q .; then
    echo apk
  else
    echo ipk
  fi
}

# 从 ImageBuilder 自带的构建目录取内核版本，ipk 线全靠它对齐 vmlinux-btf
detect_kernel_version() {
  local ib="$1" v=""
  v=$(find "$ib/build_dir" -maxdepth 3 -type d -name 'linux-[0-9]*' 2>/dev/null | head -1 | sed 's|.*/linux-||')
  if [ -z "$v" ]; then
    v=$(find "$ib" -maxdepth 6 -name 'kernel_[0-9]*.ipk' 2>/dev/null | head -1 | sed 's|.*/kernel_||; s|~.*||')
  fi
  printf '%s' "$v"
}

install_daede_apk() {
  case "$INSTALL_DAEDE" in
    1|true|yes) ;;
    *)
      echo "Skipping luci-app-daede release APK download."
      return
      ;;
  esac

  local packages_dir="$WORK_DIR/imagebuilder/packages"
  local daede_url
  if [ -n "$DAEDE_APK_URL" ]; then
    daede_url="$DAEDE_APK_URL"
  else
    daede_url="$(resolve_release_asset "luci-app-daede-" "-${DAEDE_ARCH}.apk" "luci-app-daede APK for ${DAEDE_ARCH}")"
  fi
  mkdir -p "$packages_dir"

  # Strip the -<arch> suffix from the release filename. apk mkndx indexes the
  # package under its canonical name-version.apk; if the file keeps the
  # -x86_64 suffix the index entry points to a missing file and the build
  # fails with "package mentioned in index not found".
  local fname="${daede_url##*/}"
  fname="${fname%-${DAEDE_ARCH}.apk}.apk"

  echo "Downloading luci-app-daede APK: $daede_url -> $fname"
  curl -L --retry 8 --retry-delay 5 --connect-timeout 30 \
    -o "$packages_dir/$fname" "$daede_url"
}

# 24.10 线：内核不带 BTF，必须把 vmlinux-btf 一起放进本地包目录；
# dae / daed 仍取所选 ImmortalWrt feed 里的版本。
install_daede_ipk() {
  local kernel_version="$1"
  local packages_dir="$WORK_DIR/imagebuilder/packages"
  mkdir -p "$packages_dir"

  if [ "$INSTALL_DAEDE" = "1" ] || [ "$INSTALL_DAEDE" = "true" ] || [ "$INSTALL_DAEDE" = "yes" ]; then
    local daede_url
    daede_url="$(resolve_release_asset "luci-app-daede_" "_all.ipk" "luci-app-daede IPK (noarch)")"
    echo "Downloading luci-app-daede IPK: $daede_url"
    curl -L --retry 8 --retry-delay 5 --connect-timeout 30 \
      -o "$packages_dir/${daede_url##*/}" "$daede_url"
  else
    echo "Skipping luci-app-daede release IPK download."
  fi

  # 内核与 BTF 必须同版本，差一个小版本都会让 dae 加载失败。
  if [ -z "$kernel_version" ]; then
    echo "ERROR: cannot detect kernel version from the ImageBuilder, refusing to guess a vmlinux-btf version." >&2
    return 1
  fi

  local btf_url
  btf_url="$(resolve_release_asset "vmlinux-btf_${kernel_version}-" "_${DAEDE_ARCH}.ipk" "vmlinux-btf IPK for kernel ${kernel_version}")"
  echo "Downloading vmlinux-btf IPK: $btf_url"
  curl -L --retry 8 --retry-delay 5 --connect-timeout 30 \
    -o "$packages_dir/${btf_url##*/}" "$btf_url"

  echo "vmlinux-btf pinned to kernel $kernel_version"
}

if [ ! -s "$IB_ARCHIVE" ]; then
  curl -L --retry 8 --retry-delay 5 --connect-timeout 30 \
    -o "$IB_ARCHIVE" "$IMAGEBUILDER_URL"
fi

rm -rf "$WORK_DIR/imagebuilder"
mkdir -p "$WORK_DIR/imagebuilder"
tar --use-compress-program=unzstd -xf "$IB_ARCHIVE" -C "$WORK_DIR/imagebuilder" --strip-components=1

cp -a files "$WORK_DIR/imagebuilder/files"

PKG_FORMAT="$(detect_pkg_format "$WORK_DIR/imagebuilder")"
case "$PKG_FORMAT" in
  apk)
    install_daede_apk
    ;;
  ipk)
    KERNEL_VERSION="$(detect_kernel_version "$WORK_DIR/imagebuilder")"
    install_daede_ipk "$KERNEL_VERSION"
    # vmlinux-btf 只存在于 release，不在 feed，必须显式加进包列表
    case " $EXTRA_PACKAGES " in
      *" vmlinux-btf "*) ;;
      *) EXTRA_PACKAGES="$EXTRA_PACKAGES vmlinux-btf" ;;
    esac
    ;;
  *)
    echo "ERROR: unsupported package format $PKG_FORMAT" >&2
    exit 1
    ;;
  esac

cd "$WORK_DIR/imagebuilder"

# ipk 线要先建索引，否则 preflight 的 make manifest 看不见刚放进 packages/ 的包。
# 24.10 的 ImageBuilder 默认开着 CONFIG_SIGNATURE_CHECK，但镜像里没有 key-build，
# ipk 索引的 usign 步骤会直接把 make 打挂；apk 线有 --allow-untrusted 兜底，ipk 没有。
if [ "$PKG_FORMAT" = "ipk" ]; then
  sed -i \
    -e 's/^CONFIG_SIGNATURE_CHECK=y/# CONFIG_SIGNATURE_CHECK is not set/' \
    .config
  echo "Rebuilding local opkg index..."
  make package_index
fi

echo "SDK line: $SDK_LINE ($IB_RELEASE)"
echo "Package format: $PKG_FORMAT"
if [ "$PKG_FORMAT" = "ipk" ]; then
  echo "Kernel (vmlinux-btf match): ${KERNEL_VERSION:-unknown}"
fi
echo "Version: $VERSION"
echo "Target: $TARGET"
echo "Profile: $PROFILE"
echo "Rootfs part size: ${ROOTFS_PARTSIZE}MB"
echo "Extra packages: $EXTRA_PACKAGES"
echo "Install daede: $INSTALL_DAEDE"
echo "Daede release: $DAEDE_REPO@$DAEDE_RELEASE_TAG ($DAEDE_ARCH)"
mkdir -p "$OUT_DIR"
echo "extra_packages=$EXTRA_PACKAGES" > "$OUT_DIR/.extra_packages"

diagnose_failure() {
  cat >&2 <<'EOF'

ImageBuilder failed.

Common causes for this daede image:
- The selected ImmortalWrt snapshot ImageBuilder and package feeds are out of sync.
  Example: base packages require a newer libubox/libblobmsg-json than the public feed provides.
- luci-app-daede or one of the dae/daed eBPF dependencies
  (kmod-sched-bpf / kmod-veth / kmod-xdp-sockets-diag)
  is missing from the selected target's kmod feed for the current kernel version.
- The luci-app-daede release APK was not copied into the local ImageBuilder packages
  directory, or its architecture does not match the selected target.

About BTF:
- 25.12 kernels enable CONFIG_DEBUG_INFO_BTF by default, so dae/daed reads
  /sys/kernel/btf/vmlinux directly and needs no vmlinux-btf package.
- 24.10 kernels do NOT (# CONFIG_DEBUG_INFO_BTF is not set), so the image must carry the
  matching vmlinux-btf IPK from the kenzok8/openwrt-daede release. Its filename embeds
  the kernel version; a mismatch between the ImageBuilder kernel and that package is the
  most common 24.10 failure. ImageBuilder cannot compile vmlinux-btf itself.

Next choices:
- Retry later with the same SDK line URL after ImmortalWrt feeds finish syncing.
- For 24.10, set SDK_RELEASE to a release whose vmlinux-btf IPK exists in the daede
  release, or rebuild vmlinux-btf for that kernel via the openwrt-daede SDK gate first.
- Override DAEDE_RELEASE_TAG, DAEDE_ARCH, or DAEDE_APK_URL if you need a specific
  luci-app-daede release asset.
- Verify kmod-* packages exist for the target+kernel combo via:
    make manifest PROFILE="$PROFILE" PACKAGES="$EXTRA_PACKAGES"
EOF
}

if [ "$PREFLIGHT" = "1" ] || [ "$PREFLIGHT" = "true" ]; then
  echo "Running package manifest preflight..."
  if ! make manifest PROFILE="$PROFILE" PACKAGES="$EXTRA_PACKAGES"; then
    diagnose_failure
    exit 1
  fi
fi

# Slim image formats: keep only squashfs EFI img.gz + qcow2 + vmdk
sed -i \
  -e 's/^CONFIG_TARGET_ROOTFS_EXT4FS=y/# CONFIG_TARGET_ROOTFS_EXT4FS is not set/' \
  -e 's/^CONFIG_TARGET_ROOTFS_TARGZ=y/# CONFIG_TARGET_ROOTFS_TARGZ is not set/' \
  -e 's/^CONFIG_VDI_IMAGES=y/# CONFIG_VDI_IMAGES is not set/' \
  -e 's/^CONFIG_VHDX_IMAGES=y/# CONFIG_VHDX_IMAGES is not set/' \
  -e 's/^CONFIG_ISO_IMAGES=y/# CONFIG_ISO_IMAGES is not set/' \
  -e 's/^CONFIG_GRUB_IMAGES=y/# CONFIG_GRUB_IMAGES is not set/' \
  .config

if ! make image \
    PROFILE="$PROFILE" \
    PACKAGES="$EXTRA_PACKAGES" \
    FILES=files \
    BIN_DIR="$OUT_DIR" \
    EXTRA_IMAGE_NAME="$EXTRA_IMAGE_NAME" \
    ROOTFS_PARTSIZE="$ROOTFS_PARTSIZE"; then
  diagnose_failure
  exit 1
fi

# Rename to short friendly names — the immortalwrt prefix is too long for GitHub UI
	cd "$OUT_DIR"
	for f in *-squashfs-combined-efi.img.gz;  do [ -f "$f" ] && mv "$f" daede-squashfs-efi.img.gz;  done
	for f in *-squashfs-combined-efi.qcow2; do [ -f "$f" ] && mv "$f" daede-squashfs-efi.qcow2; done
	for f in *-squashfs-combined-efi.vmdk;  do [ -f "$f" ] && mv "$f" daede-squashfs-efi.vmdk;  done
	for f in *-kernel.bin;                do [ -f "$f" ] && mv "$f" daede-kernel.bin;            done
	for f in *-rootfs.tar.gz;             do [ -f "$f" ] && mv "$f" daede-rootfs.tar.gz;         done
	for f in *.manifest;                  do [ -f "$f" ] && mv "$f" daede.manifest;              done
	for f in *.bom.cdx.json;              do [ -f "$f" ] && mv "$f" daede.bom.cdx.json;          done
	for f in *.img.gz *.qcow2 *.vmdk *.bin *.tar.gz *.manifest *.bom.cdx.json; do
	  [ -f "$f" ] || continue
	  sha256sum "$f"
	done > sha256sums
	# Build date in CST for release notes
	BUILD_DATE="$(TZ='Asia/Shanghai' date '+%F %H:%M CST')"
	BTF_NOTE=""
	if [ "$PKG_FORMAT" = "ipk" ]; then
		BTF_NOTE="- **内核 BTF**：vmlinux-btf ${KERNEL_VERSION}（24.10 内核不带内置 BTF）
- **Netkit**：不可用（内核 6.6 < 6.7），dae 自动回落 veth"
	fi
	cat > BUILD-MANIFEST.txt <<BODYEOF
## daede 固件 · ${EXTRA_IMAGE_NAME}

基于 ImmortalWrt ${IB_RELEASE}，x86-64 通用镜像，squashfs-only。

### 推荐下载

| 格式 | 适用场景 | 文件 |
|------|----------|------|
| **img.gz** | 物理机 dd 写盘 / PVE 导入 | daede-squashfs-efi.img.gz |
| **qcow2** | QEMU / Proxmox VE | daede-squashfs-efi.qcow2 |
| **vmdk** | VMware ESXi / Workstation | daede-squashfs-efi.vmdk |

> 额外：`daede-rootfs.tar.gz` 裸文件系统，可用于 LXC 容器转换。

### 镜像详情

- **系统类型**：squashfs（只读根 + overlay 可写层，抗断电）
- **分区**：combined（含分区表 + 引导，直接 dd）
- **启动**：EFI
- **根分区大小**：${ROOTFS_PARTSIZE} MB
- **SDK 线**：${SDK_LINE} · ${IB_RELEASE} · ${PKG_FORMAT}
${BTF_NOTE}
- **构建日期**：${BUILD_DATE}
- **ImageBuilder**：${IMAGEBUILDER_URL}

### 预装软件

\`$(cat "$OUT_DIR/.extra_packages" 2>/dev/null || echo "$EXTRA_PACKAGES")\`

### 校验

\`\`\`bash
sha256sum -c sha256sums --ignore-missing
\`\`\`
BODYEOF
	ls -la "$OUT_DIR"
