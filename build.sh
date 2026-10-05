#!/bin/bash

function _help(){
    echo
    echo "Build EDK2 for Rockchip RK3588 platforms."
    echo
    echo "Usage: build.sh [options]"
    echo
    echo "Options:"
    echo "  -d, --device DEV            Build for DEV, or 'all'."
    echo "  -r, --release MODE          Release mode for building, default is 'DEBUG', 'RELEASE' alternatively."
    echo "  -t, --toolchain TOOLCHAIN   Set toolchain, default is 'GCC'."
    echo "  --open-tfa ENABLE           Use open-source TF-A submodule. Default: ${OPEN_TFA}"
    echo "  --tfa-flags \"FLAGS\"         Flags appended to open TF-A build process."
    echo "  --edk2-flags \"FLAGS\"        Flags appended to the EDK2 build process."
    echo "  --skip-patchsets            Skip applying upstream submodule patchsets during development."
    echo "  -C, --clean                 Clean workspace and output."
    echo "  -D, --distclean             Clean up all files that are not in repo."
    echo "  -h, --help                  Show this help."
    echo
    exit "${1}"
}

function _error() { echo "${@}" >&2; exit 1; }

function apply_patchset() {
    ${SKIP_PATCHSETS} && return 0

    local patches_dir="$1"
    local target_dir="$2"

    [ ! -d "${patches_dir}" ] && return 0

    if [ ! -d "${target_dir}" ]; then
        echo "Patchset target directory does not exist: ${target_dir}"
        return 1
    fi

    echo "Checking patchset ${patches_dir} for ${target_dir}"

    local patchset_name=$(basename "${patches_dir}")
    local patchset_marker="${target_dir}/.patchset_${patchset_name}"

    if [ ! -f "${patchset_marker}" ] || [ "${patches_dir}" -nt "${patchset_marker}" ]; then
        echo "Patchset needs to be (re)applied"
        if ! git -C "${target_dir}" reset --hard || ! git -C "${target_dir}" clean -xfd; then
            echo "Failed to reset git repository - aborting"
            return 1
        fi
    else
        echo "Patchset already applied - skipping"
        return 0
    fi

    local patch_file
    local patch_count=0

    for patch_file in "${patches_dir}"/*.patch; do
        [ -f "${patch_file}" ] || continue

        local patch_name=$(basename "${patch_file}")
        echo "Patch ${patch_count}: ${patch_name}"

        if patch -p1 -d "${target_dir}" < "${patch_file}"; then
            echo "  Successfully applied"
            ((patch_count++))
        else
            echo "  Failed to apply - aborting"
            return 1
        fi
    done

    touch "${patchset_marker}"

    echo "Patchset summary: ${patch_count} applied"
    return 0
}

function _build_idblock() {
    echo " => Building idblock.bin"
    pushd ${WORKSPACE}

    FLASHFILES="FlashHead.bin FlashData.bin FlashBoot.bin"
    rm -f rk35*_spl_loader_*.bin idblock.bin rk35*_ddr_*.bin rk35*_usbplug*.bin UsbHead.bin ${FLASHFILES}

    DDRBIN_RKBIN=$(grep '^FlashData' ${ROOTDIR}/misc/rkbin/RKBOOT/${MINIALL_INI} | cut -d = -f 2-)
    SPL_RKBIN=$(grep '^FlashBoot' ${ROOTDIR}/misc/rkbin/RKBOOT/${MINIALL_INI} | cut -d = -f 2-)

    DDRBIN="${ROOTDIR}/misc/rkbin/${DDRBIN_RKBIN}"

    #
    # SPL v1.13 has broken SD card support!
    # Use v1.12 instead.
    #
    # SPL="${ROOTDIR}/misc/rkbin/${SPL_RKBIN}"
    SPL="${ROOTDIR}/misc/rk3588_spl_v1.12.bin"

    # Create idblock.bin
    ${ROOTDIR}/misc/tools/${MACHINE_TYPE}/mkimage -n rk3588 -T rksd -d ${DDRBIN}:${SPL} idblock.bin

    popd
    echo " => idblock.bin build done"
}

function _build_fit() {
    echo " => Building FIT"
    pushd ${WORKSPACE}

    BL31_RKBIN=$(grep '^PATH=.*_bl31_' ${ROOTDIR}/misc/rkbin/RKTRUST/${TRUST_INI} | cut -d = -f 2-)
    BL32_RKBIN=$(grep '^PATH=.*_bl32_' ${ROOTDIR}/misc/rkbin/RKTRUST/${TRUST_INI} | cut -d = -f 2-)

    BL31="${ROOTDIR}/misc/rkbin/${BL31_RKBIN}"
    BL32="${ROOTDIR}/misc/rkbin/${BL32_RKBIN}"

    if ${OPEN_TFA}; then
        BL31="${ROOTDIR}/arm-trusted-firmware/build/${TFA_PLAT}/${RELEASE_TYPE,,}/bl31/bl31.elf"
    fi

    rm -f bl31_0x*.bin ${WORKSPACE}/BL33_AP_UEFI.Fv ${SOC_L}_${DEVICE}_EFI.its

    ${ROOTDIR}/misc/extractbl31.py ${BL31}

    #
    # Emit one FIT image node per BL31 PT_LOAD segment.
    #
    # Which segments exist is up to the linker, and it moves with the TF-A
    # version: through v2.12 rk3588 produced a single writable segment plus
    # PMUSRAM, while v2.15 turns on the platform linker script and splits the
    # main one into separate read-only and read-write segments. A fixed list in
    # the .its silently drops any segment nobody thought to add -- BL31 is then
    # loaded with that part of itself missing and dies before it can report why.
    #
    # extractbl31.py names each file after its load address, zero padded to
    # eight hex digits, so sorting the names sorts them by address. The lowest
    # is where BL31 is entered and becomes the FIT's "firmware"; the rest have
    # to be listed as loadables or they are not loaded at all.
    #
    ATF_NODES="$(mktemp)"
    ATF_LOADABLES=""
    ATF_INDEX=0

    for ATF_SEG in $(ls bl31_0x*.bin 2>/dev/null | sort); do
        ATF_ADDR="${ATF_SEG#bl31_}"
        ATF_ADDR="${ATF_ADDR%.bin}"
        ATF_INDEX=$((ATF_INDEX + 1))

        cat >> "${ATF_NODES}" <<EOF
		atf-${ATF_INDEX} {
			description = "ARM Trusted Firmware";
			data = /incbin/("./${ATF_SEG}");
			type = "firmware";
			arch = "arm64";
			os = "arm-trusted-firmware";
			compression = "none";
			load = <${ATF_ADDR}>;
			hash {
				algo = "sha256";
			};
		};
EOF

        if [ ${ATF_INDEX} -gt 1 ]; then
            ATF_LOADABLES="${ATF_LOADABLES}\"atf-${ATF_INDEX}\", "
        fi
    done

    if [ ${ATF_INDEX} -eq 0 ]; then
        rm -f "${ATF_NODES}"
        _error "No BL31 segments extracted from ${BL31}"
    fi

    cp ${BL32} ${WORKSPACE}/bl32.bin
    cp ${ROOTDIR}/misc/${SOC_L}_spl.dtb ${WORKSPACE}/${DEVICE}.dtb
    cp ${WORKSPACE}/Build/${PLATFORM_NAME}/${RELEASE_TYPE}_${TOOLCHAIN}/FV/BL33_AP_UEFI.Fv ${WORKSPACE}/
    sed -e "s,@DEVICE@,${DEVICE},g" \
        -e "s|@ATF_LOADABLES@|${ATF_LOADABLES}|" \
        -e "/@ATF_IMAGES@/r ${ATF_NODES}" \
        -e "/@ATF_IMAGES@/d" \
        ${ROOTDIR}/misc/uefi_${SOC_L}.its > ${SOC_L}_${DEVICE}_EFI.its
    rm -f "${ATF_NODES}"
    ${ROOTDIR}/misc/tools/${MACHINE_TYPE}/mkimage -f ${SOC_L}_${DEVICE}_EFI.its -E ${DEVICE}_EFI.itb

    popd
    echo " => FIT build done"
}

function _pack_image() {
    _build_idblock
    _build_fit

    echo " => Building 8MB NOR FLASH IMAGE"
    cp ${WORKSPACE}/Build/${PLATFORM_NAME}/${RELEASE_TYPE}_${TOOLCHAIN}/FV/NOR_FLASH_IMAGE.fd ${WORKSPACE}/RK3588_NOR_FLASH.img

    # GPT at 0x0, size:0x4400
    dd if=${ROOTDIR}/misc/rk3588_spi_nor_gpt.img of=${WORKSPACE}/RK3588_NOR_FLASH.img
    # idblock at 0x8000
    dd if=${WORKSPACE}/idblock.bin of=${WORKSPACE}/RK3588_NOR_FLASH.img bs=1K seek=32
    # FIT Image at 0x100000
    dd if=${WORKSPACE}/${DEVICE}_EFI.itb of=${WORKSPACE}/RK3588_NOR_FLASH.img bs=1K seek=1024
    cp ${WORKSPACE}/RK3588_NOR_FLASH.img ${ROOTDIR}/
}

function _build(){
    local DEVICE="${1}"; shift

    #
    # Grab platform parameters
    #
    if [ -f "configs/${DEVICE}.conf" ]
    then source "configs/${DEVICE}.conf"
    else _error "Device configuration not found"
    fi
    if [ -f "configs/${SOC}.conf" ]
    then source "configs/${SOC}.conf"
    else _error "SoC configuration not found"
    fi
    typeset -l SOC_L="$SOC"

    rm -f "${OUTDIR}/RK35*_NOR_FLASH.img"

    #
    # Build TF-A
    #
    if ${OPEN_TFA}; then
        apply_patchset "${ROOTDIR}/arm-trusted-firmware-patches" "${ROOTDIR}/arm-trusted-firmware" || exit 1

        pushd arm-trusted-firmware

        if [ ${RELEASE_TYPE} == "DEBUG" ]; then
            DEBUG=1
        else
            DEBUG=0
        fi

        echo " > make PLAT=${TFA_PLAT} DEBUG=${DEBUG} ${TFA_VERBOSE_FLAGS} all ${TFA_FLAGS}"
        make PLAT=${TFA_PLAT} DEBUG=${DEBUG} ${TFA_VERBOSE_FLAGS} all ${TFA_FLAGS}

        popd
    fi

    #
    # Build EDK2
    #
    apply_patchset "${ROOTDIR}/edk2-patches" "${ROOTDIR}/edk2" || exit 1
    apply_patchset "${ROOTDIR}/devicetree/mainline/patches" "${ROOTDIR}/devicetree/mainline/upstream" || exit 1

    [ -d "${WORKSPACE}/Conf" ] || mkdir -p "${WORKSPACE}/Conf"

    export GCC_AARCH64_PREFIX="${CROSS_COMPILE}"
    export CLANG38_AARCH64_PREFIX="${CROSS_COMPILE}"
    PACKAGES_PATH="${ROOTDIR}"
    PACKAGES_PATH+=":${ROOTDIR}/devicetree"
    PACKAGES_PATH+=":${ROOTDIR}/edk2"
    PACKAGES_PATH+=":${ROOTDIR}/edk2-non-osi"
    PACKAGES_PATH+=":${ROOTDIR}/edk2-platforms"
    PACKAGES_PATH+=":${ROOTDIR}/edk2-rockchip"
    PACKAGES_PATH+=":${ROOTDIR}/edk2-rockchip-non-osi"
    export PACKAGES_PATH

    echo " > make -C ${ROOTDIR}/edk2/BaseTools"
    make -C "${ROOTDIR}/edk2/BaseTools"
    echo " > source ${ROOTDIR}/edk2/edksetup.sh --reconfig"
    source "${ROOTDIR}/edk2/edksetup.sh" --reconfig

    # The exact command is echoed into the log before it runs, so a failed
    # build can be reproduced by hand from the log alone.
    echo " > build -n ${EDK2_JOBS} -a AARCH64 -t ${TOOLCHAIN} -p ${ROOTDIR}/${DSC_FILE} -b ${RELEASE_TYPE} ${EDK2_VERBOSE_FLAGS} ..."
    build \
        -n "${EDK2_JOBS}" \
        -a AARCH64 \
        -t "${TOOLCHAIN}" \
        -p "${ROOTDIR}/${DSC_FILE}" \
        -b "${RELEASE_TYPE}" \
        ${EDK2_VERBOSE_FLAGS} \
        -D FIRMWARE_VER="${GIT_COMMIT}" \
        -D NETWORK_ALLOW_HTTP_CONNECTIONS=TRUE \
        -D NETWORK_ISCSI_ENABLE=TRUE \
        -D INCLUDE_TFTP_COMMAND=TRUE \
        --pcd gRockchipTokenSpaceGuid.PcdFitImageFlashAddress=0x100000 \
        ${EDK2_FLAGS}

    #
    # Compile final image
    #
    _pack_image

    echo "Build done: RK3588_NOR_FLASH.img"
}

function _clean() { rm --one-file-system --recursive --force "${OUTDIR}"/workspace "${OUTDIR}"/RK3588_*.img; }
function _distclean() { if [ -d .git ]; then git clean -xdf; else _clean; fi; }

#
# Logging
#
# Every line the build writes - to stdout and to stderr, including the output
# of the TF-A and EDK2 sub-builds, of patch/make/dd/mkimage and of shell
# traces - is mirrored into a timestamped file under ./logs. Nothing is
# filtered, so the file on disk is a complete transcript of the run and can be
# analysed after the fact.
#
function _log_setup() {
    local name="${DEVICE:-unknown}"
    [ "${name}" == "all" ] && name="all"

    LOG_DIR="${ROOTDIR}/logs"
    mkdir -p "${LOG_DIR}" || _error "Cannot create log directory ${LOG_DIR}"
    LOG_FILE="${LOG_DIR}/${name}-${RELEASE_TYPE}-$(date +%Y%m%d-%H%M%S).log"

    # Mirror stdout+stderr to the console and to the log file. tee is run with
    # unbuffered stdio (stdbuf) so that the last lines reach the file even if
    # the build is killed or the machine goes down mid-compile.
    if command -v stdbuf >/dev/null 2>&1; then
        exec > >(stdbuf -o0 -e0 tee -a "${LOG_FILE}") 2>&1
    else
        exec > >(tee -a "${LOG_FILE}") 2>&1
    fi

    trap _log_summary EXIT

    echo "==============================================================================="
    echo "build.sh started : $(date -Is)"
    echo "host             : $(uname -srm)"
    echo "working dir      : ${OUTDIR}"
    echo "device           : ${DEVICE}"
    echo "release          : ${RELEASE_TYPE}"
    echo "toolchain        : ${TOOLCHAIN}"
    echo "open-tfa         : ${OPEN_TFA}"
    echo "tfa-flags        : ${TFA_FLAGS}"
    echo "edk2-flags       : ${EDK2_FLAGS}"
    echo "edk2 verbose     : ${EDK2_VERBOSE_FLAGS}"
    echo "edk2 jobs        : ${EDK2_JOBS}"
    echo "log file         : ${LOG_FILE}"
    echo "==============================================================================="
}

#
# Runs before anything is compiled, so that a missing host tool is reported as
# "you are missing iasl" rather than as a confusing module build failure deep
# in the EDK2 output.
#
function _check_build_deps() {
    local missing=()
    local tool

    # Invoked directly by this script or by the EDK2 build rules.
    #   iasl      : compiles the platform DSDT (DSC-side, via $(ASL_PATH)).
    #               Omitted from most distro images and easy to overlook.
    #   python3   : BaseTools and the FIT/patch helpers.
    #   make/git/patch/dd/mkimage : everything else in the pipeline.
    for tool in iasl python3 make git patch dd; do
        command -v "${tool}" >/dev/null 2>&1 || missing+=("${tool}")
    done

    # Cross compiler, unless we happen to be building natively on aarch64.
    if [ "$(uname -m)" != "aarch64" ]; then
        command -v "${CROSS_COMPILE}gcc" >/dev/null 2>&1 || missing+=("${CROSS_COMPILE}gcc")
    fi

    # misc/extractbl31.py runs unconditionally as part of building the FIT
    # image, and imports pyelftools. Note this is needed *after* EDK2 and TF-A
    # have built, so without the check a missing module surfaces only at the
    # very end of a successful build.
    if ! python3 -c "import elftools" >/dev/null 2>&1; then
        missing+=("python3-pyelftools")
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        echo "Missing build tools: ${missing[*]}" >&2
        echo >&2
        echo "On Debian/Ubuntu install them with:" >&2
        echo "    sudo apt install acpica-tools python3-pyelftools uuid-dev \\" >&2
        echo "                     device-tree-compiler gcc-aarch64-linux-gnu" >&2
        _error "Aborting before the build starts."
    fi

    # Only needed for boards whose device tree is built from source.
    if ! command -v dtc >/dev/null 2>&1; then
        echo "WARNING: 'dtc' not found (device-tree-compiler) - device trees built"
        echo "         from a .dts source will fail; prebuilt .dtb blobs are unaffected."
    fi

    echo "host tools       : iasl $(iasl -v 2>/dev/null | awk '/version/{print $NF; exit}'), $(python3 --version 2>&1), $(${CROSS_COMPILE}gcc --version 2>/dev/null | head -1)"
}

#
# Runs from the EXIT trap set up by _log_setup, so the log ends with the exit
# status and a pointer to every log file the sub-builds produced on their own.
#
function _log_summary() {
    local rc=$?
    local log

    echo "==============================================================================="
    echo "build.sh finished: $(date -Is)"
    echo "exit code        : ${rc}"

    if [ -n "${WORKSPACE}" ] && [ -n "${PLATFORM_NAME}" ] && [ -n "${RELEASE_TYPE}" ] && [ -n "${TOOLCHAIN}" ]; then
        for log in "${WORKSPACE}/Build/${PLATFORM_NAME}/"*.log \
                   "${WORKSPACE}/Build/${PLATFORM_NAME}/${RELEASE_TYPE}_${TOOLCHAIN}/"*.log; do
            [ -f "${log}" ] && echo "sub-build log    : ${log}"
        done
    fi

    echo "full log         : ${LOG_FILE}"

    if [ "${rc}" -ne 0 ]; then
        echo
        echo "Build FAILED (exit ${rc}). The complete output is in:"
        echo "    ${LOG_FILE}"
    fi
    echo "==============================================================================="
    return 0
}

#
# Default variables
#
typeset -l DEVICE
typeset -u RELEASE_TYPE
DEVICE=""
RELEASE_TYPE=DEBUG
TOOLCHAIN=GCC
OPEN_TFA=true
TFA_FLAGS=""
EDK2_FLAGS=""
SKIP_PATCHSETS=false
CLEAN=false
DISTCLEAN=false
OUTDIR="${PWD}"

#
# Verbosity of the two compilers. Both are turned up so that the on-disk log
# is self-contained; an explicitly empty value (e.g. EDK2_VERBOSE_FLAGS=) drops
# the extra detail and leaves the compiler at its own default:
#   EDK2_VERBOSE_FLAGS : "-v" makes EDK2 print every compile command line
#   TFA_VERBOSE_FLAGS  : "V=1" makes the TF-A makefile echo every command
#   EDK2_JOBS          : "0" keeps EDK2's automatic job count; "1" builds
#                        serially, which makes the log strictly ordered and
#                        much easier to read when something goes wrong
EDK2_VERBOSE_FLAGS="${EDK2_VERBOSE_FLAGS--v}"
TFA_VERBOSE_FLAGS="${TFA_VERBOSE_FLAGS-V=1}"
EDK2_JOBS="${EDK2_JOBS-0}"

#
# Get options
#
OPTS=$(getopt -o "d:r:t:CDh" -l "device:,release:,toolchain:,open-tfa:,tfa-flags:,edk2-flags:,skip-patchsets,clean,distclean,help" -n build.sh -- "${@}") || _help $?
eval set -- "${OPTS}"
while true; do
    case "${1}" in
        -d|--device) DEVICE="${2}"; shift 2 ;;
        -r|--release) RELEASE_TYPE="${2}"; shift 2 ;;
        -t|--toolchain) TOOLCHAIN="${2}"; shift 2 ;;
        --open-tfa) OPEN_TFA="${2}"; shift 2 ;;
        --tfa-flags) TFA_FLAGS="${2}"; shift 2 ;;
        --edk2-flags) EDK2_FLAGS="${2}"; shift 2 ;;
        --skip-patchsets) SKIP_PATCHSETS=true; shift ;;
        -C|--clean) CLEAN=true; shift ;;
        -D|--distclean) DISTCLEAN=true; shift ;;
        -h|--help) _help 0; shift ;;
        --) shift; break ;;
        *) break ;;
    esac
done
if [[ -n "${@}" ]]; then
    echo "Invalid additional arguments '${@}'"
    _help 1
fi

if "${DISTCLEAN}"; then _distclean; exit "$?"; fi
if "${CLEAN}"; then _clean; exit "$?"; fi

[ -z "${DEVICE}" ] && _help 1
[ -f "configs/${DEVICE}.conf" ] || [ "${DEVICE}" == "all" ] || _error "Device configuration not found"

#
# Get machine architecture
#
MACHINE_TYPE=$(uname -m)

# Fix-up possible differences in reported arch
if [ ${MACHINE_TYPE} == 'arm64' ]; then
    MACHINE_TYPE='aarch64'
elif [ ${MACHINE_TYPE} == 'amd64' ]; then
    MACHINE_TYPE='x86_64'
fi

if [ ${MACHINE_TYPE} != 'aarch64' ]; then
    export CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}"
fi

GIT_COMMIT="$(git describe --tags --always)" || GIT_COMMIT="unknown"

export WORKSPACE="${OUTDIR}/workspace"
[ -d "${WORKSPACE}" ] || mkdir "${WORKSPACE}"

ROOTDIR="$(realpath "$(dirname "$0")")"
cd "${ROOTDIR}" || exit 1

# Exit on first error
set -e

# From here on, capture everything (stdout+stderr) to ./logs/<file>.log as well
# as the console. Anything that goes wrong later is therefore on disk.
_log_setup
_check_build_deps

if [ "${DEVICE}" == "all" ]
then
    for i in configs/*.conf; do
        DEV="$(basename "$i" .conf)"
        if [ "${DEV}" != "RK3588" ]
        then
            echo "Building ${DEV}"
            _build "${DEV}"
        fi
    done
else
    _build "${DEVICE}"
fi
