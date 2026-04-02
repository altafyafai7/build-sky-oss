#!/usr/bin/env bash

# Constants
WORKDIR="$(pwd)"
if [ "$KVER" == "6.6" ]; then
  RELEASE="v0.3"
elif [ "$KVER" == "5.10" ]; then
  RELEASE="v0.3"
elif [ "$KVER" == "6.1" ]; then
  RELEASE="v0.1"
fi

KERNEL_NAME="SKY-OSS-"
USER="Altaf"
HOST="AltafYafai"
TIMEZONE="Asia/Kolkata"
ANYKERNEL_REPO="https://github.com/AltafYafai/AnyKernel3"
ANYKERNEL_BRANCH="sky"

# Fixed Logic: 5.10 & 6.1 use gki_defconfig, others use quartix_defconfig
if [ "$KVER" == "5.10" ]; then
  KERNEL_DEFCONFIG="gki_defconfig"
elif [ "$KVER" == "6.1" ]; then
  KERNEL_DEFCONFIG="gki_defconfig"
else
  KERNEL_DEFCONFIG="gki_defconfig"
fi

if [ "$KVER" == "6.6" ]; then
  KERNEL_REPO="https://github.com/ramabondanp/android_kernel_common-6.6.git"
  KERNEL_BRANCH="android15-6.6-staging"
elif [ "$KVER" == "6.1" ]; then
  KERNEL_REPO="https://github.com/altafyafai7/6.1-oss.git"
  KERNEL_BRANCH="main"
elif [ "$KVER" == "5.10" ]; then
  KERNEL_REPO="https://github.com/altafyafai7/android_kernel_xiaomi_sky_upstream.git"
  KERNEL_BRANCH="smy"
fi
# sky (5.10 & 6.1): merge vendor configs so hardware_info.ko gets built,
# which exports set_tpinfo_gki needed by FT8720 and NT36672C touchscreen drivers.
if [ "$KVER" == "5.10" ]; then
  DEFCONFIG_TO_MERGE="arch/arm64/configs/vendor/sky_GKI.config"
elif [ "$KVER" == "6.1" ]; then
  DEFCONFIG_TO_MERGE="arch/arm64/configs/sky_GKI.fragment"
else
  DEFCONFIG_TO_MERGE=""
fi
GKI_RELEASES_REPO="https://github.com/suvojeet-sengupta/build-vortex"
#Change the clang by removing the (#) sign then apply
#CLANG_URL="https://github.com/linastorvaldz/idk/releases/download/clang-r547379/clang.tgz"
#CLANG_URL="https://github.com/LineageOS/android_prebuilts_clang_kernel_linux-x86_clang-r416183b/archive/refs/heads/lineage-20.0.tar.gz"
#CLANG_URL="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/main-kernel-2025/clang-r536225.tar.gz"
#CLANG_URL="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/62cdcefa89e31af2d72c366e8b5ef8db84caea62/clang-r547379.tar.gz"
#CLANG_URL="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/105aba85d97a53d364585ca755752dae054b49e8/clang-r584948b.tar.gz"
#CLANG_URL="https://github.com/greenforce-project/greenforce_clang/releases/download/20260210/gf-clang-23.0.0-20260210.tar.gz"
CLANG_URL="https://github.com/greenforce-project/greenforce_clang/releases/download/20260302/gf-clang-23.0.0-20260302.tar.gz"
#CLANG_URL="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/42d2c090c14c9c7f4dfd365ae551e2b959dc775c/clang-r584948b.tar.gz"
#CLANG_URL="https://github.com/linastorvaldz/gki-builder/releases/download/clang-r487747c/clang-r487747c.tar.gz"
#CLANG_URL="$(./clang.sh slim)"
CLANG_BRANCH=""
AK3_ZIP_NAME="$KERNEL_NAME-REL-KVER-VARIANT-BUILD_DATE.zip"
OUTDIR="$WORKDIR/out"
KSRC="$WORKDIR/ksrc"
KERNEL_PATCHES="$WORKDIR/kernel-patches"

# Handle error
exec > >(tee $WORKDIR/build.log) 2>&1
trap 'error "Failed at line $LINENO [$BASH_COMMAND]"' ERR

# Import functions
source $WORKDIR/functions.sh

# Install erofs-utils (needed for vendor_dlkm.img)
sudo apt-get update && sudo apt-get install -y erofs-utils

# Set timezone
sudo timedatectl set-timezone "$TIMEZONE" || export TZ="$TIMEZONE"

# Clone kernel source
step_msg "Source Sync" "Cloning $(simplify_gh_url "$KERNEL_REPO") [$KERNEL_BRANCH]"
git clone -q --depth=1 $KERNEL_REPO -b $KERNEL_BRANCH $KSRC

cd $KSRC
COMMIT_HASH=$(git rev-parse --short HEAD)
COMMIT_MSG=$(git log -1 --pretty=format:"%s")
LINUX_VERSION=$(make kernelversion)
LINUX_VERSION_CODE=${LINUX_VERSION//./}
DEFCONFIG_FILE=$(find ./arch/arm64/configs -name "$KERNEL_DEFCONFIG")
cd $WORKDIR

send_msg "🚀 *SKY Build Triggered*
━━━━━━━━━━━━━━━━━━━━
📱 *Device:* \`sky (Redmi 12 5G)\`
⚙️ *Target:* \`$KVER\`
🆔 *Commit:* [\`$COMMIT_HASH\`]($KERNEL_REPO/commit/$COMMIT_HASH)
📝 *Msg:* \`$COMMIT_MSG\`
👤 *User:* \`$USER\`
━━━━━━━━━━━━━━━━━━━━"

# Set Kernel variant
VARIANT="Stock"

# Replace Placeholder in zip name
AK3_ZIP_NAME=${AK3_ZIP_NAME//KVER/$LINUX_VERSION}
AK3_ZIP_NAME=${AK3_ZIP_NAME//VARIANT/$VARIANT}

# Download Clang
CLANG_DIR="$WORKDIR/clang"
CLANG_BIN="${CLANG_DIR}/bin"
if [ -z "$CLANG_BRANCH" ]; then
  step_msg "Toolchain" "Downloading Clang [Release]"
  wget -qO clang-archive "$CLANG_URL"
  mkdir -p "$CLANG_DIR"
  case "$(basename $CLANG_URL)" in
    *.tar.* | *.tgz)
      tar -xf clang-archive -C "$CLANG_DIR"
      ;;
    *.7z)
      7z x clang-archive -o${CLANG_DIR}/ -bd -y > /dev/null
      ;;
    *)
      error "Unsupported file format"
      ;;
  esac
  rm clang-archive

  if [ $(find "$CLANG_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l) -eq 1 ] \
    && [ $(find "$CLANG_DIR" -mindepth 1 -maxdepth 1 -type f | wc -l) -eq 0 ]; then
    SINGLE_DIR=$(find "$CLANG_DIR" -mindepth 1 -maxdepth 1 -type d)
    mv $SINGLE_DIR/* $CLANG_DIR/
    rm -rf $SINGLE_DIR
  fi
else
  step_msg "Toolchain" "Cloning Clang [$CLANG_BRANCH]"
  git clone --depth=1 -q "$CLANG_URL" -b "$CLANG_BRANCH" "$CLANG_DIR"
fi

# Clone GNU Assembler
step_msg "Toolchain" "Cloning GNU Assembler"
GAS_DIR="$WORKDIR/gas"
git clone --depth=1 -q \
  https://android.googlesource.com/platform/prebuilts/gas/linux-x86 \
  -b main \
  "$GAS_DIR"

export PATH="${CLANG_BIN}:${GAS_DIR}:$PATH"

# Extract clang version
COMPILER_STRING=$(clang -v 2>&1 | head -n 1 | sed 's/(https..*//' | sed 's/ version//')

# ── Detect final LTO mode for build notification ──────────────────────────────
# (LTO detection logic is inside build.sh further down, but we need variables here if we use them)

cd $KSRC

# Declare needed variables
export KBUILD_BUILD_USER="$USER"
export KBUILD_BUILD_HOST="$HOST"
export KBUILD_BUILD_TIMESTAMP=$(date)
export KCFLAGS="-w"
if [ $(echo "$LINUX_VERSION_CODE" | head -c1) -eq 6 ]; then
  MAKE_ARGS=(
    LLVM=1
    ARCH=arm64
    CROSS_COMPILE=aarch64-linux-gnu-
    CROSS_COMPILE_COMPAT=arm-linux-gnueabi-
    -j$(nproc --all)
    O=$OUTDIR
  )
else
  MAKE_ARGS=(
    LLVM=1
    LLVM_IAS=1
    ARCH=arm64
    CROSS_COMPILE=aarch64-linux-gnu-
    CROSS_COMPILE_COMPAT=arm-linux-gnueabi-
    -j$(nproc --all)
    O=$OUTDIR
  )
fi

KERNEL_IMAGE="$OUTDIR/arch/arm64/boot/Image"
MODULE_SYMVERS="$OUTDIR/Module.symvers"
if [ $(echo "$LINUX_VERSION_CODE" | head -c1) -eq 6 ]; then
  KMI_CHECK="$WORKDIR/py/kmi-check-6.x.py"
else
  KMI_CHECK="$WORKDIR/py/kmi-check-5.x.py"
fi
## Build GKI
step_msg "Configuration" "Generating $KERNEL_DEFCONFIG"
cd $KSRC
make ${MAKE_ARGS[@]} $KERNEL_DEFCONFIG

if [ "$DEFCONFIG_TO_MERGE" ]; then
  step_msg "Configuration" "Merging Vendor Fragments"
  if [ -f "scripts/kconfig/merge_config.sh" ]; then
    ./scripts/kconfig/merge_config.sh -m -O $OUTDIR $OUTDIR/.config $DEFCONFIG_TO_MERGE
    make ${MAKE_ARGS[@]} olddefconfig
  else
    error "scripts/kconfig/merge_config.sh does not exist in the kernel source"
  fi
fi

# set localversion — AFTER merge so sky_GKI.config -gki doesn't override it
if [ "$TODO" == "kernel" ]; then
  cd $KSRC
  LATEST_COMMIT_HASH=$(git rev-parse --short HEAD)
  if [ $STATUS == "BETA" ]; then
    SUFFIX="$LATEST_COMMIT_HASH"
  else
    SUFFIX="${RELEASE}@${LATEST_COMMIT_HASH}"
  fi
  $KSRC/scripts/config --file $OUTDIR/.config --set-str CONFIG_LOCALVERSION "-$KERNEL_NAME-sky/$SUFFIX"
  $KSRC/scripts/config --file $OUTDIR/.config --disable CONFIG_LOCALVERSION_AUTO
  sed -i 's/echo "+"/# echo "+"/g' $KSRC/scripts/setlocalversion
  make ${MAKE_ARGS[@]} olddefconfig
  log "Localversion set: -$KERNEL_NAME-sky/$SUFFIX"
  cd $WORKDIR
fi

# ── Apply LTO mode based on $LTO env variable ────────────────────────────────
LTO="${LTO:-thin}"
$KSRC/scripts/config --file $OUTDIR/.config --disable CONFIG_LTO_NONE
if [[ "$LTO" == "full" ]]; then
  $KSRC/scripts/config --file $OUTDIR/.config --disable CONFIG_LTO_CLANG_THIN
  $KSRC/scripts/config --file $OUTDIR/.config --enable  CONFIG_LTO_CLANG
  $KSRC/scripts/config --file $OUTDIR/.config --enable  CONFIG_LTO_CLANG_FULL
  step_msg "Optimization" "Full LTO Enabled"
else
  $KSRC/scripts/config --file $OUTDIR/.config --disable CONFIG_LTO_CLANG_FULL
  $KSRC/scripts/config --file $OUTDIR/.config --enable  CONFIG_LTO_CLANG
  $KSRC/scripts/config --file $OUTDIR/.config --enable  CONFIG_LTO_CLANG_THIN
  step_msg "Optimization" "Thin LTO Enabled"
fi

# ── Detect final LTO mode for build notification ──────────────────────────────
if grep -q "^CONFIG_LTO_CLANG_THIN=y" "$OUTDIR/.config"; then
  LTO_MODE="Thin LTO"
elif grep -q "^CONFIG_LTO_CLANG_FULL=y" "$OUTDIR/.config"; then
  LTO_MODE="Full LTO"
else
  LTO_MODE="Disabled"
fi

# ── Get Latest Commit Info ───────────────────────────────────────────────────
cd $KSRC
COMMIT_HASH=$(git rev-parse --short HEAD)
COMMIT_MSG=$(git log -1 --pretty=format:"%s")
cd $WORKDIR

# ── Telegram build notification message ───────────────────────────────────────
text=$(
  cat << EOF
✨ *$KERNEL_NAME OSS — SKY* ✨
━━━━━━━━━━━━━━━━━━━━
🛠 *Technical Details:*
• 🐧 *Kernel Version:* \`$LINUX_VERSION\`
• ⚡ *LTO Mode:* \`$LTO_MODE\`
• 🛡 *Compiler:* \`$COMPILER_STRING\`
• 📅 *Build Date:* \`$KBUILD_BUILD_TIMESTAMP\`
• 🆔 *Commit:* [\`$COMMIT_HASH\`]($KERNEL_REPO/commit/$COMMIT_HASH)
• 📝 *Changes:* \`$COMMIT_MSG\`

👥 *Credits:* 
• @lostark13: OSS Source
• @AltafYafai: Project Maintainer

🌐 *Source:* [GitHub]($KERNEL_REPO)
━━━━━━━━━━━━━━━━━━━━
EOF
)

# Upload defconfig if we are doing defconfig
if [ $TODO == "defconfig" ]; then
  log "Uploading defconfig..."
  upload_file $OUTDIR/.config "📄 *Kernel Configuration (defconfig)*"
  exit 0
fi

# Build the actual kernel
step_msg "Compilation" "Starting Kernel Build"
cd $KSRC
make ${MAKE_ARGS[@]} 2>&1 | live_log

# Check KMI Function symbol
step_msg "Verification" "Checking KMI Symbols"
if [ $(echo "$LINUX_VERSION_CODE" | head -c1) -eq 6 ]; then
  $KMI_CHECK "$KSRC/android/abi_gki_aarch64.stg" "$MODULE_SYMVERS" || true
else
  $KMI_CHECK "$KSRC/android/abi_gki_aarch64.xml" "$MODULE_SYMVERS" || true
fi

# Return to the initial working directory (Post-compiling steps)
cd $WORKDIR
# ----------------------------------------------------

## Post-compiling stuff
cd $WORKDIR

# Build vendor_dlkm.img
build_vendor_dlkm() {
  step_msg "Packaging" "Building vendor_dlkm.img"
  local STAGING_DIR="$WORKDIR/staging"
  local MODULES_LIST=""
  
  # Try to find modules list in various locations
  if [ -f "$KSRC/modules.list.msm.sky" ]; then
    MODULES_LIST="$KSRC/modules.list.msm.sky"
  elif [ -f "$WORKDIR/modules.list.msm.sky" ]; then
    MODULES_LIST="$WORKDIR/modules.list.msm.sky"
  elif [ -f "$WORKDIR/sky-t-oss/modules.list.msm.sky" ]; then
    MODULES_LIST="$WORKDIR/sky-t-oss/modules.list.msm.sky"
  fi
  
  rm -rf "$STAGING_DIR"
  mkdir -p "$STAGING_DIR/lib/modules/$LINUX_VERSION"

  if [ -n "$MODULES_LIST" ]; then
    log "Using modules list: $(basename $MODULES_LIST)"
    while read -r module; do
      [[ -z "$module" || "$module" =~ ^# ]] && continue
      local find_res=$(find "$OUTDIR" -name "$module" | head -n 1)
      if [ -n "$find_res" ]; then
        cp "$find_res" "$STAGING_DIR/lib/modules/$LINUX_VERSION/"
      fi
    done < "$MODULES_LIST"
  else
    log "Modules list not found, copying all modules from $OUTDIR..."
    find "$OUTDIR" -name "*.ko" -exec cp {} "$STAGING_DIR/lib/modules/$LINUX_VERSION/" \;
  fi

  # Run depmod
  depmod -b "$STAGING_DIR" "$LINUX_VERSION"

  # Create EROFS image
  mkfs.erofs -z "lz4hc,9" -T 0 "$WORKDIR/vendor_dlkm.img" "$STAGING_DIR"

  if [ -f "$WORKDIR/vendor_dlkm.img" ]; then
    step_msg "Packaging" "vendor_dlkm.img Ready"
    mkdir -p "$WORKDIR/artifacts"
    mv "$WORKDIR/vendor_dlkm.img" "$WORKDIR/artifacts/"
  else
    error "Failed to create vendor_dlkm.img"
  fi
}

build_vendor_dlkm

# Collect modules
step_msg "Packaging" "Collecting Kernel Modules"
mkdir -p $WORKDIR/modules
find $OUTDIR -name "*.ko" -exec cp {} $WORKDIR/modules/ \;

# Zip modules separately
cd $WORKDIR/modules
MODULES_ZIP="modules-${LINUX_VERSION}.zip"
zip -r9 $WORKDIR/$MODULES_ZIP ./*
cd $WORKDIR

# Upload modules separately
upload_file "$WORKDIR/$MODULES_ZIP" "📦 *Kernel Modules (.ko)*"

# Clone AnyKernel
step_msg "AnyKernel" "Cloning AK3 Template"
git clone -q --depth=1 $ANYKERNEL_REPO -b $ANYKERNEL_BRANCH anykernel

# Copy modules to AnyKernel (Standard path for GKI modules in AK3)
mkdir -p $WORKDIR/anykernel/modules/vendor/lib/modules
cp $WORKDIR/modules/*.ko $WORKDIR/anykernel/modules/vendor/lib/modules/

# Set kernel string and basic configuration in anykernel
sed -i "s/IS_SLOT_DEVICE=.*/IS_SLOT_DEVICE=1;/g" $WORKDIR/anykernel/anykernel.sh
sed -i "s/PATCH_VBMETA_FLAG=.*/PATCH_VBMETA_FLAG=1;/g" $WORKDIR/anykernel/anykernel.sh

if [ "$STATUS" == "BETA" ]; then
  BUILD_DATE=$(date -d "$KBUILD_BUILD_TIMESTAMP" +"%Y%m%d-%H%M")
  AK3_ZIP_NAME=${AK3_ZIP_NAME//BUILD_DATE/$BUILD_DATE}
  AK3_ZIP_NAME=${AK3_ZIP_NAME//-REL/}
  sed -i \
    "s/kernel.string=.*/kernel.string=${KERNEL_NAME} | ${LINUX_VERSION} | Stock/g" \
    $WORKDIR/anykernel/anykernel.sh
else
  AK3_ZIP_NAME=${AK3_ZIP_NAME//-BUILD_DATE/}
  AK3_ZIP_NAME=${AK3_ZIP_NAME//REL/$RELEASE}
  sed -i \
    "s/kernel.string=.*/kernel.string=${KERNEL_NAME} ${RELEASE} | ${LINUX_VERSION} | Stock/g" \
    $WORKDIR/anykernel/anykernel.sh
fi

# Zip the anykernel
cd anykernel
step_msg "AnyKernel" "Creating Flashable ZIP"
cp $KERNEL_IMAGE .
zip -r9 $WORKDIR/$AK3_ZIP_NAME ./*
cd $OLDPWD

mkdir -p $WORKDIR/artifacts
echo "BASE_NAME=$KERNEL_NAME-$VARIANT" >> $GITHUB_ENV
if [ -f "$WORKDIR/$AK3_ZIP_NAME" ]; then
  mv $WORKDIR/$AK3_ZIP_NAME $WORKDIR/artifacts/
fi

if [ "${LAST_BUILD}" == "true" ] || [ "${STATUS}" != "BETA" ]; then
  (
    echo "LINUX_VERSION=$LINUX_VERSION"
    echo "KERNEL_NAME=$KERNEL_NAME"
    echo "RELEASE_REPO=$(simplify_gh_url "$GKI_RELEASES_REPO")"
  ) >> $WORKDIR/artifacts/info.txt
fi

# Send detailed message first
send_msg "$text"

# Always upload ZIP if found
CAPTION="💎 *Premium Build Complete*
━━━━━━━━━━━━━━━━━━━━
📄 *File:* \`$AK3_ZIP_NAME\`
🧪 *Variant:* \`$VARIANT\`
⚡ *LTO:* \`$LTO_MODE\`
✅ *Result:* \`GKI-SUCCESS\`
━━━━━━━━━━━━━━━━━━━━"

if [ -f "$WORKDIR/artifacts/$AK3_ZIP_NAME" ]; then
  upload_file "$WORKDIR/artifacts/$AK3_ZIP_NAME" "$CAPTION"
else
  # Fallback: if specific name fails, try any zip in artifacts
  ZIP_FILE=$(ls $WORKDIR/artifacts/*.zip 2>/dev/null | head -n 1)
  if [ -f "$ZIP_FILE" ]; then
    upload_file "$ZIP_FILE" "$CAPTION"
  else
    send_msg "❌ Error: ZIP file not found in artifacts directory."
  fi
fi

if [ $STATUS == "BETA" ]; then
  upload_file "$WORKDIR/build.log"
fi

echo "$text" > $WORKDIR/artifacts/release_notes.txt
exit 0
