#!/bin/bash
########################################
### Run a virtual machine using Qemu ###
########################################

# Virtual machine parameters
RAM_AMOUNT="2048M"
RAM_AMOUNT_MAX="${RAM_AMOUNT}"
CPU_CORE_COUNT=2
BASE_DISK_FILE="base-disk.qcow2" # Backing file for the main image
PORT_FORWARDS="tcp::8888-:8080"  # List of portforwards in the Qemu format separated by spaces (TLDR: tcp/udp::HOST-:GUEST)
USB_FILTER="-1:-1:-1:-1:0"       # List of allowed USB devices in the Qemu format separated by '|' characters
OS_TYPE="linux"                  # Operating system type {linux|windows|other}
GVT_ENABLED="false"              # Enable Intel Graphics Virtualization (might need machine type q35)
AUDIO_ENABLED="false"            # Enable audio device access throught PulseAudio
VIDEO_ENABLED="false"            # Enable video device access via USB passthrough
SHARED_FOLDER=""                 # Path to shared folder using virtio-fs
HEADLESS="false"                 # Run in headless mode

# Default parameters
EXT_CONFIG_FILE="${0}.config"
SUDO_KVM="false"
QEMU_EXECUTABLE="/usr/bin/qemu-system-x86_64"
QEMU_IMG="/usr/bin/qemu-img"
QEMU_VIRTIOFSD="/usr/lib/qemu/virtiofsd"
CMD_BOOT="-boot c"         # Boot from the virtual disk by default
NAME="default"             # The virtual machine's name
DISK_FILE="default.qcow2"  # The overlay disk file, used to boot
QEMU_EXTRA_PARAMETERS=""   # No extra parameters by default
VGA_TYPE="virtio"
CPU_EXTRA_FLAGS=""
MACHINE_EXTRA_FLAGS=""
MEMORY_EXTRA_FLAGS=""
QEMU_WRAPPER=""
DISPLAY_TYPE="spice-app,gl=on"
VIRTIOFS_SOCKET_NAME="sock-virtiofs"

# Source the config file
if [[ -f "${EXT_CONFIG_FILE}"  ]]; then
    echo "Reading config file ${EXT_CONFIG_FILE}..."
    . "${EXT_CONFIG_FILE}"
fi

# Functions
function usage() {
    echo "Initialization: ${0} init SIZE_IN_GB" >&2
    echo "Usage: ${0} NAME {cdrom FILE|snapshot|info|create}" >&2
    exit 1
}

function check_base_disk_file() {
    if ! [[ -f "${BASE_DISK_FILE}" ]]; then
        echo "ERROR! Base disk file missing, please use \"${0} init SIZE_IN_GB\" to fix the problem"
        exit 1
    fi
}

function check_overlay_disk_file() {
    if ! [[ -f "${DISK_FILE}" ]]; then
        echo "ERROR! Overlay disk file missing, use \"${0} ${1} create\" to fix the problem"
        exit 1
    fi
}

function get_base_disk_size() {
    ${QEMU_IMG} info "${BASE_DISK_FILE}" | grep "virtual size" | grep -o -P '\([0-9]* bytes\)' | grep -o -P '[0-9]*'
}

function get_video_device() {
    PATH_VIDEO="/sys/class/video4linux"

    if [[ -z "${1}" ]]; then
        VIDEO_DEV="${PATH_VIDEO}/$(ls -1 ${PATH_VIDEO} 2>/dev/null | head -n1)"
    else
        VIDEO_DEV="${PATH_VIDEO}/${1}"
    fi

    FILE_PATH_PID="${VIDEO_DEV}/device/../idProduct"
    FILE_PATH_VID="${VIDEO_DEV}/device/../idVendor"
    if [[ ! -f "${FILE_PATH_PID}" ]] || [[ ! -f "${FILE_PATH_VID}" ]]; then
        return 1
    fi

    echo "0x$(cat ${FILE_PATH_VID}):0x$(cat ${FILE_PATH_PID})"
    return 0
}

# Process first command line parameter
if ! [[ -z "${1}" ]]; then
    case "${1}" in
        # Initialize virtual machine
        init)
            if ! [[ -f "${BASE_DISK_FILE}" ]]; then
                ${QEMU_IMG} create -f qcow2 -o cluster_size=2M "${BASE_DISK_FILE}" "${2}G"
                exit "${?}"
            else
                echo "Base disk file ${BASE_DISK_FILE} already exists"
                exit 1
            fi
            ;;

        *)
            if [[ "${1}" =~ ^.*\.qcow2$ ]]; then
                DISK_FILE="${1}"
                NAME="$(rev <<< ${1} | cut -d '.' -f 2- | rev)"
            else
                DISK_FILE="${1}.qcow2"
                NAME="${1}"
            fi
            ;;
    esac
else
    usage
fi

# Read machine specific config
VM_CONFIG_FUNCTION="machine_config_${NAME}"
VM_CONFIG_TYPE=$(type -t "${VM_CONFIG_FUNCTION}")
if [[ "${VM_CONFIG_TYPE}" == "function" ]]; then
    echo "Setting machine specific options for ${NAME}..."
    ${VM_CONFIG_FUNCTION}
fi

# Base disk sanity check
check_base_disk_file

# Process rest of the command line parameters
if ! [[ -z "${2}" ]]; then
    case "${2}" in
        # Boot from a cdrom image
        cdrom|image)
            if [[ -f "${3}" ]]; then
                echo "Booting from cdrom image ${3}..."
                CMD_BOOT="-cdrom ${3} -boot d"
            else
                usage
            fi
            ;;

        # Boot in snapshot mode, discard all changes on shutdown
        snapshot|volatile|temp|temporary|freeze)
            echo "WARNING! Running in snapshot mode. All changes to the disk will be discarded on shutdown."
            QEMU_EXTRA_PARAMETERS+=" -snapshot "
            ;;

        # Show disk information
        info|status)
            ${QEMU_IMG} info "${DISK_FILE}"
            exit 0
            ;;

        # Create overlay disk file
        create)
            if ! [[ -f "${DISK_FILE}" ]]; then
                ${QEMU_IMG} create -b "${BASE_DISK_FILE}" -f qcow2 -o cluster_size=2M "${DISK_FILE}" "$(get_base_disk_size)"
                exit "${?}"
            else
                echo "File ${DISK_FILE} already exists"
                exit 1
            fi
            ;;

        *)
            usage
            ;;
    esac
fi

# Process portforwards
PORT_FORWARD_PARAMS=""
for i in ${PORT_FORWARDS}; do
    PORT_FORWARD_PARAMS+=",hostfwd=${i}"
done

# Process OS type
case "${OS_TYPE}" in
    windows|Windows|WINDOWS)
        echo "Optimizing for Windows guest..."
        VGA_TYPE="qxl"
        CPU_EXTRA_FLAGS+=",hv_relaxed,hv_spinlocks=0x1fff,hv_vapic,hv_time"
        MACHINE_EXTRA_FLAGS+=",type=pc,kernel_irqchip=on"
        QEMU_EXTRA_PARAMETERS+=" -global PIIX4_PM.disable_s3=1 -global PIIX4_PM.disable_s4=1 -rtc base=localtime "
        ;;

    *)
        echo "Running with normal guest settings..."
        ;;
esac

# Process ACPI and SMBIOS
for i in *.acpi.bin; do
    [ -e "${i}" ] || [ -L "${i}" ] || continue
    echo "Found acpi table file ${i}..."
    QEMU_EXTRA_PARAMETERS+=" -acpitable file=${i} "
done
if [[ -f "smbios.bin" ]]; then
    echo "Using custom smbios file..."
    QEMU_EXTRA_PARAMETERS+=" -smbios file=smbios.bin "
fi

# Run sanity checks
check_overlay_disk_file ${1}

# Process audio
if [[ "${AUDIO_ENABLED}" == "true" ]]; then
    PA_SOCKET=$(eval $(pax11publish -i); echo ${PULSE_SERVER})
    QEMU_EXTRA_PARAMETERS+=" -device ich9-intel-hda -device hda-micro,audiodev=hda -audiodev pa,id=hda,server=${PA_SOCKET} "
fi

# Process video
if [[ "${VIDEO_ENABLED}" == "true" ]]; then
    if VIDEO_ENABLED_DEVICE=$(get_video_device); then
        USB_FILTER="-1:${VIDEO_ENABLED_DEVICE}:-1:1|${USB_FILTER}"
    fi
fi

# Check gvt-g
if [[ "${GVT_ENABLED}" == "true" ]]; then
    echo "GVT enabled..."
    GVT_DEVICE=$(sudo ./gvtg.sh create)
    if [[ -d "${GVT_DEVICE}" ]]; then
        echo "GVT-G detected, using card ${GVT_DEVICE}...";
        QEMU_EXTRA_PARAMETERS+=" -device vfio-pci,sysfsdev=${GVT_DEVICE},x-igd-opregion=on,display=on "
        # Run thread to change memlock limit
        (
            while ! QEMU_PID=$(pidof -s qemu-system-x86_64); do
                sleep 0.1
            done
            sudo prlimit --memlock=unlimited:unlimited -p "${QEMU_PID}"
            echo "MEMLOCK limit raised successfully..."
        )&
    else
        echo "GVT-G error."
        exit 1
    fi
fi

# Check if kvm group is needed
if [[ "${SUDO_KVM}" == "true" ]]; then
    QEMU_WRAPPER="sudo -g kvm"
fi

# Process shared folders
if [[ "${SHARED_FOLDER}" != "" ]]; then
    VIRTIOFS_SOCKET="$(dirname ${0})/${VIRTIOFS_SOCKET_NAME}"

    sudo ${QEMU_VIRTIOFSD} --socket-path="${VIRTIOFS_SOCKET}" -o source="${SHARED_FOLDER}" &
    VIRTIOFS_PID="$!"
    while ! pgrep -P "${VIRTIOFS_PID}" > /dev/null; do
        sleep 0.5
    done
    sudo chown "$(whoami):$(whoami)" "${VIRTIOFS_SOCKET}"

    QEMU_EXTRA_PARAMETERS+=" -chardev socket,id=virtiofs0,path=${VIRTIOFS_SOCKET} "
    QEMU_EXTRA_PARAMETERS+=" -device vhost-user-fs-pci,queue-size=1024,chardev=virtiofs0,tag=myfs "
    MEMORY_EXTRA_FLAGS+="-object memory-backend-file,id=mem,size=${RAM_AMOUNT},mem-path=/dev/shm,share=on"
    MACHINE_EXTRA_FLAGS+=",memory-backend=mem"
fi

# Check for headless mode
if [[ "${HEADLESS}" == "true" ]]; then
    DISPLAY_TYPE="none"
else
    QEMU_EXTRA_PARAMETERS+=" -device virtio-serial-pci "
    QEMU_EXTRA_PARAMETERS+=" -device virtserialport,chardev=spicechannel0,name=com.redhat.spice.0 "
    QEMU_EXTRA_PARAMETERS+=" -chardev spicevmc,id=spicechannel0,name=vdagent "
    QEMU_EXTRA_PARAMETERS+=" -device ich9-usb-ehci1,id=usb "
    QEMU_EXTRA_PARAMETERS+=" -device ich9-usb-uhci1,masterbus=usb.0,firstport=0,multifunction=on "
    QEMU_EXTRA_PARAMETERS+=" -device ich9-usb-uhci2,masterbus=usb.0,firstport=2 "
    QEMU_EXTRA_PARAMETERS+=" -device ich9-usb-uhci3,masterbus=usb.0,firstport=4 "
    QEMU_EXTRA_PARAMETERS+=" -chardev spicevmc,name=usbredir,id=usbredirchardev1 "
    QEMU_EXTRA_PARAMETERS+=" -device usb-redir,filter=${USB_FILTER},chardev=usbredirchardev1,id=usbredirdev1 "
    QEMU_EXTRA_PARAMETERS+=" -chardev spicevmc,name=usbredir,id=usbredirchardev2 "
    QEMU_EXTRA_PARAMETERS+=" -device usb-redir,filter=${USB_FILTER},chardev=usbredirchardev2,id=usbredirdev2 "
    QEMU_EXTRA_PARAMETERS+=" -chardev spicevmc,name=usbredir,id=usbredirchardev3 "
    QEMU_EXTRA_PARAMETERS+=" -device usb-redir,filter=${USB_FILTER},chardev=usbredirchardev3,id=usbredirdev3 "
fi

# Run the virtual machine
${QEMU_WRAPPER} ${QEMU_EXECUTABLE} \
  -enable-kvm \
  -no-hpet \
  -machine accel=kvm${MACHINE_EXTRA_FLAGS} \
  -smp cores=${CPU_CORE_COUNT},threads=1,sockets=1 \
  -m size=${RAM_AMOUNT},maxmem=${RAM_AMOUNT_MAX} ${MEMORY_EXTRA_FLAGS} \
  -cpu host${CPU_EXTRA_FLAGS} \
  -net nic,model=virtio \
  -net user${PORT_FORWARD_PARAMS} \
  -vga ${VGA_TYPE} \
  -display ${DISPLAY_TYPE} \
  -object iothread,id=iothread0 \
  -device virtio-scsi-pci,id=scsi0,iothread=iothread0,num_queues=4 \
  -drive id=hd-scsi0,file=${DISK_FILE},if=none,format=qcow2,discard=unmap,detect-zeroes=unmap,aio=threads,cache=none \
  -device scsi-hd,drive=hd-scsi0 \
  ${QEMU_EXTRA_PARAMETERS} \
  ${CMD_BOOT}

# Remove gvt-g
if [[ "${GVT_ENABLED}" == "true" ]]; then
    echo "Removing gvt-g device..."
    sudo ./gvtg.sh remove
fi
