#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${OUT_DIR:-${ROOT_DIR}/out}"
DEFCONFIG="${DEFCONFIG:-pissarro_user_defconfig}"
TOOLCHAIN_DIR="${TOOLCHAIN_DIR:-/tmp/proton-clang-13}"
JOBS="${JOBS:-$(nproc --all)}"
TARGET="${TARGET:-Image.gz-dtb}"

if [[ ! -x "${TOOLCHAIN_DIR}/bin/clang" ]]; then
	echo "Missing clang at ${TOOLCHAIN_DIR}/bin/clang"
	echo "Set TOOLCHAIN_DIR to a Proton Clang 13 checkout, for example:"
	echo "  TOOLCHAIN_DIR=/path/to/proton-clang-13 ./build_pissarro_image.sh"
	exit 1
fi

mkdir -p "${OUT_DIR}"

echo "==> Kernel: ${ROOT_DIR}"
echo "==> Out: ${OUT_DIR}"
echo "==> Defconfig: ${DEFCONFIG}"
echo "==> Toolchain: ${TOOLCHAIN_DIR}"
echo "==> Jobs: ${JOBS}"
echo "==> Target: ${TARGET}"

make -C "${ROOT_DIR}" O="${OUT_DIR}" ARCH=arm64 "${DEFCONFIG}"

make -C "${ROOT_DIR}" -j"${JOBS}" O="${OUT_DIR}" \
	ARCH=arm64 \
	CC="${TOOLCHAIN_DIR}/bin/clang" \
	CLANG_TRIPLE=aarch64-linux-gnu- \
	CROSS_COMPILE="${TOOLCHAIN_DIR}/bin/aarch64-linux-gnu-" \
	CROSS_COMPILE_ARM32="${TOOLCHAIN_DIR}/bin/arm-linux-gnueabi-" \
	LD="${TOOLCHAIN_DIR}/bin/ld.lld" \
	STRIP="${TOOLCHAIN_DIR}/bin/llvm-strip" \
	AS="${TOOLCHAIN_DIR}/bin/llvm-as" \
	AR="${TOOLCHAIN_DIR}/bin/llvm-ar" \
	NM="${TOOLCHAIN_DIR}/bin/llvm-nm" \
	OBJCOPY="${TOOLCHAIN_DIR}/bin/llvm-objcopy" \
	OBJDUMP="${TOOLCHAIN_DIR}/bin/llvm-objdump" \
	CONFIG_NO_ERROR_ON_MISMATCH=y \
	"${TARGET}"

IMAGE="${OUT_DIR}/arch/arm64/boot/Image.gz-dtb"
if [[ ! -f "${IMAGE}" ]]; then
	echo "Build finished but ${IMAGE} was not found"
	exit 1
fi

echo "==> Done: ${IMAGE}"
ls -lh "${IMAGE}"
