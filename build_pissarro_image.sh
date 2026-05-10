#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${OUT_DIR:-${ROOT_DIR}/out}"
DIST_DIR="${DIST_DIR:-${ROOT_DIR}/dist}"
DEFCONFIG="${DEFCONFIG:-pissarro_user_defconfig}"
JOBS="${JOBS:-$(nproc --all)}"
TARGET="${TARGET:-Image.gz-dtb}"

TOOLCHAIN_DIR="${TOOLCHAIN_DIR:-${ROOT_DIR}/toolchains/proton-clang-13}"
TOOLCHAIN_REPO="${TOOLCHAIN_REPO:-https://gitlab.com/LeCmnGend/proton-clang.git}"
TOOLCHAIN_BRANCH="${TOOLCHAIN_BRANCH:-clang-13}"

need_cmd() {
	if ! command -v "$1" >/dev/null 2>&1; then
		echo "Missing required command: $1"
		exit 1
	fi
}

fetch_toolchain() {
	if [[ -x "${TOOLCHAIN_DIR}/bin/clang" ]]; then
		return
	fi

	need_cmd git
	echo "==> Proton Clang 13 not found, cloning once..."
	mkdir -p "$(dirname "${TOOLCHAIN_DIR}")"
	git clone --depth=1 -b "${TOOLCHAIN_BRANCH}" "${TOOLCHAIN_REPO}" "${TOOLCHAIN_DIR}"

	if [[ ! -x "${TOOLCHAIN_DIR}/bin/clang" ]]; then
		echo "Toolchain clone finished, but clang is still missing:"
		echo "  ${TOOLCHAIN_DIR}/bin/clang"
		exit 1
	fi
}

build_image() {
	mkdir -p "${OUT_DIR}" "${DIST_DIR}"

	echo "==> Kernel: ${ROOT_DIR}"
	echo "==> Out: ${OUT_DIR}"
	echo "==> Dist: ${DIST_DIR}"
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

	local image="${OUT_DIR}/arch/arm64/boot/Image.gz-dtb"
	if [[ ! -f "${image}" ]]; then
		echo "Build finished but ${image} was not found"
		exit 1
	fi

	cp -f "${image}" "${DIST_DIR}/Image.gz-dtb"
	echo "==> Done:"
	ls -lh "${image}" "${DIST_DIR}/Image.gz-dtb"
}

need_cmd make
need_cmd nproc
fetch_toolchain
build_image
