#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${OUT_DIR:-${ROOT_DIR}/out}"
DIST_DIR="${DIST_DIR:-${ROOT_DIR}/dist}"
DEFCONFIG="${DEFCONFIG:-pissarro_user_defconfig}"
if [[ -z "${JOBS:-}" ]]; then
	if command -v nproc >/dev/null 2>&1; then
		JOBS="$(nproc --all)"
	else
		JOBS="4"
	fi
fi
TARGET="${TARGET:-Image.gz-dtb}"
AUTO_INSTALL_DEPS="${AUTO_INSTALL_DEPS:-1}"

TOOLCHAIN_DIR="${TOOLCHAIN_DIR:-${ROOT_DIR}/toolchains/proton-clang-13}"
TOOLCHAIN_REPO="${TOOLCHAIN_REPO:-https://gitlab.com/LeCmnGend/proton-clang.git}"
TOOLCHAIN_BRANCH="${TOOLCHAIN_BRANCH:-clang-13}"

install_missing_deps() {
	local missing=()
	local packages=()
	local cmd

	for cmd in "$@"; do
		if command -v "${cmd}" >/dev/null 2>&1; then
			continue
		fi

		missing+=("${cmd}")
		case "${cmd}" in
		make) packages+=("make") ;;
		git) packages+=("git") ;;
		bc) packages+=("bc") ;;
		flex) packages+=("flex") ;;
		bison) packages+=("bison") ;;
		perl) packages+=("perl") ;;
		python3) packages+=("python3") ;;
		nproc) packages+=("coreutils") ;;
		*) packages+=("${cmd}") ;;
		esac
	done

	if [[ ! -f /usr/include/openssl/bio.h ]]; then
		missing+=("openssl/bio.h")
		packages+=("libssl-dev")
	fi

	if [[ "${#missing[@]}" -eq 0 ]]; then
		return
	fi

	readarray -t packages < <(printf '%s\n' "${packages[@]}" | sort -u)

	echo "==> Missing required command(s): ${missing[*]}"
	if [[ "${AUTO_INSTALL_DEPS}" != "1" ]]; then
		echo "AUTO_INSTALL_DEPS=0, please install package(s): ${packages[*]}"
		exit 1
	fi

	if ! command -v apt-get >/dev/null 2>&1; then
		echo "apt-get not found. Please install package(s): ${packages[*]}"
		exit 1
	fi

	local apt=(apt-get)
	if [[ "${EUID}" -ne 0 ]]; then
		if ! command -v sudo >/dev/null 2>&1; then
			echo "sudo not found. Please install package(s) as root: ${packages[*]}"
			exit 1
		fi
		apt=(sudo apt-get)
	fi

	echo "==> Installing minimal build dependency package(s): ${packages[*]}"
	"${apt[@]}" update
	"${apt[@]}" install -y "${packages[@]}"
}

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
	export PATH="${PATH}:${TOOLCHAIN_DIR}/bin"

	echo "==> Kernel: ${ROOT_DIR}"
	echo "==> Out: ${OUT_DIR}"
	echo "==> Dist: ${DIST_DIR}"
	echo "==> Defconfig: ${DEFCONFIG}"
	echo "==> Toolchain: ${TOOLCHAIN_DIR}"
	echo "==> Jobs: ${JOBS}"
	echo "==> Target: ${TARGET}"

	make -C "${ROOT_DIR}" O="${OUT_DIR}" ARCH=arm64 "${DEFCONFIG}"
	rm -f "${OUT_DIR}/Module.symvers" "${OUT_DIR}/vmlinux.o" "${OUT_DIR}/vmlinux"
	rm -rf "${OUT_DIR}/.thinlto-cache"

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

install_missing_deps make git bc flex bison perl python3 nproc
need_cmd make
need_cmd git
need_cmd nproc
fetch_toolchain
build_image
