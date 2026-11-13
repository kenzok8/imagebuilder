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

# 24.10 线：包格式是 opkg/ipk，dae / daed 与 kmod 从所选 ImmortalWrt feed 取。
# 24.10.3 内核自带 CONFIG_DEBUG_INFO_BTF，不需要额外的 vmlinux-btf。
install_daede_ipk() {
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
    install_daede_ipk
    ;;
  *)
    echo "ERROR: unsupported package format $PKG_FORMAT" >&2
    exit 1
    ;;
  esac

cd "$WORK_DIR/imagebuilder"

# ipk 线要先建索引，否则 preflight 的 make manifest 看不见刚放进 packages/ 的包。
# 24.10 的 ImageBuilder 开着 CONFIG_SIGNATURE_CHECK 却未预生成 key-build，
# 直接建索引会卡在 usign，所以先用它自带的 _check_keys 生成一对本地密钥。
if [ "$PKG_FORMAT" = "ipk" ]; then
  make _check_keys
  echo "Rebuilding local opkg index..."
  make package_index
fi

echo "SDK line: $SDK_LINE ($IB_RELEASE)"
echo "Package format: $PKG_FORMAT"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "ib_release=$IB_RELEASE" >> "$GITHUB_OUTPUT"
  echo "pkg_format=$PKG_FORMAT" >> "$GITHUB_OUTPUT"
fi
echo "Version: $VERSION"
echo "Target: $TARGET"
echo "Profile: $PROFILE"
echo "Rootfs part size: ${ROOTFS_PARTSIZE}MB"
echo "Extra packages: $EXTRA_PACKAGES"
echo "Install daede: $INSTALL_DAEDE"
echo "Daede release: $DAEDE_REPO@$DAEDE_RELEASE_TAG ($DAEDE_ARCH)"
mkdir -p "$OUT_DIR"
echo "$EXTRA_PACKAGES" > "$OUT_DIR/.extra_packages"

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
- ImmortalWrt 24.10 and 25.12 kernels both enable CONFIG_KERNEL_DEBUG_INFO_BTF, so
  dae/daed reads /sys/kernel/btf/vmlinux directly and needs no extra package.
- Do not add vmlinux-btf to EXTRA_PACKAGES: it is not published in the feed and
  ImageBuilder cannot compile packages.

Next choices:
- Retry later with the same SDK line URL after ImmortalWrt feeds finish syncing.
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
	NETKIT_NOTE=""
	IPK_NOTE=""
	if [ "$PKG_FORMAT" = "ipk" ]; then
		NETKIT_NOTE="- **Netkit**：不可用（内核 6.6 < 6.7），dae 自动回落 veth"
		IPK_NOTE="### 24.10 线说明

- 内核 6.6，低于 netkit 需要的 6.7，\`dae\` / \`daed\` 走 veth 转发，没有 netkit 的快速路径。
- 适合千兆家用 / PPPoE 宽带；万兆网卡或大量小包并发才会显出差距。
- 包格式为 opkg/ipk，只把 \`luci-app-daede\` 的 IPK 打进固件，\`dae\` / \`daed\` 和 kmod 来自所选 ImmortalWrt feed。
- 内核自带 BTF，不需要额外的 \`vmlinux-btf\`。
"
	fi
	cat > BUILD-MANIFEST.txt <<BODYEOF
## daede 固件 · ${IB_RELEASE}

基于 ImmortalWrt ${IB_RELEASE}，x86-64 通用镜像，squashfs-only。

### 推荐下载

| 格式 | 适用场景 | 文件 |
|------|----------|------|
| **img.gz** | 物理机 dd 写盘 / PVE 导入 | daede-squashfs-efi.img.gz |
| **qcow2** | QEMU / Proxmox VE | daede-squashfs-efi.qcow2 |
| **vmdk** | VMware ESXi / Workstation | daede-squashfs-efi.vmdk |

> 额外：\`daede-rootfs.tar.gz\` 裸文件系统，可用于 LXC 容器转换。

### 镜像详情

- **系统类型**：squashfs（只读根 + overlay 可写层，抗断电）
- **分区**：combined（含分区表 + 引导，直接 dd）
- **启动**：EFI
- **根分区大小**：${ROOTFS_PARTSIZE} MB
- **SDK 线**：${SDK_LINE} · ${IB_RELEASE} · ${PKG_FORMAT}
${NETKIT_NOTE}
- **构建日期**：${BUILD_DATE}
- **ImageBuilder**：${IMAGEBUILDER_URL}

${IPK_NOTE}
### 预装软件

\`$(cat "$OUT_DIR/.extra_packages" 2>/dev/null || echo "$EXTRA_PACKAGES")\`

### 校验

\`\`\`bash
sha256sum -c sha256sums --ignore-missing
\`\`\`
BODYEOF
	ls -la "$OUT_DIR"
