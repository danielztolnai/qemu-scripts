#!/bin/bash
########################################
### Run a virtual machine using Qemu ###
########################################

# Virtual machine parameters
RAM_AMOUNT_MB=2048
CPU_CORE_COUNT=2
DISK_SIZE_GB=16
BASE_DISK_FILE="base-disk.qcow2" # Backing file for the main image
DISK_FILE="default.qcow2"        # The overlay disk file, used to boot
PORT_FORWARDS="tcp::8888-:8080"  # List of portforwards in the Qemu format separated by spaces (TLDR: tcp/udp::HOST-:GUEST)
USB_FILTER="-1:-1:-1:-1:1"       # List of allowed USB devices in the Qemu format separated by '|' characters
OS_TYPE="linux"                  # Operating system type {linux|windows|other}

# Default parameters
QEMU_EXECUTABLE="/opt/qemu-4.2.0/x86_64-softmmu/qemu-system-x86_64"
CMD_BOOT="-boot c"         # Boot from the virtual disk by default
QEMU_EXTRA_PARAMETERS=""   # No extra parameters by default

# Functions
function usage() {
    echo "Initialization: ${0} init" >&2
    echo "Usage: ${0} NAME {cdrom FILE|snapshot|info|create}" >&2
    exit 1
}

function check_disk_files() {
    if ! [[ -f "${BASE_DISK_FILE}" ]]; then
        echo "ERROR! Base disk file missing, please use \"${0} init\" to fix the problem"
        exit 1
    fi
    if ! [[ -f "${DISK_FILE}" ]]; then
        echo "ERROR! Overlay disk file missing, use \"${0} ${1} create\" to fix the problem"
        exit 1
    fi
}

# Process command line parameters
if ! [[ -z "${1}" ]]; then
    case "${1}" in
        # Initialize virtual machine
        init)
            if ! [[ -f "${BASE_DISK_FILE}" ]]; then
                qemu-img create -f qcow2 -o cluster_size=2M "${BASE_DISK_FILE}" "${DISK_SIZE_GB}G"
                exit "${?}"
            else
                echo "Base disk file ${BASE_DISK_FILE} already exists"
                exit 1
            fi
            ;;

        *)
            if [[ "${1}" =~ ^.*\.qcow2$ ]]; then
                DISK_FILE="${1}"
            else
                DISK_FILE="${1}.qcow2"
            fi
            ;;
    esac
else
    usage
fi

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
            qemu-img info "${DISK_FILE}"
            exit 0
            ;;

        # Create overlay disk file
        create)
            if ! [[ -f "${DISK_FILE}" ]]; then
                qemu-img create -b "${BASE_DISK_FILE}" -f qcow2 -o cluster_size=2M "${DISK_FILE}" "${DISK_SIZE_GB}G"
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

# Run sanity checks
check_disk_files ${1}

# Run the virtual machine
sudo -g kvm \
${QEMU_EXECUTABLE} \
  -enable-kvm \
  -machine accel=kvm \
  -accel accel=kvm,thread=multi \
  -smp cores=${CPU_CORE_COUNT},threads=1,sockets=1 \
  -m ${RAM_AMOUNT_MB} \
  -cpu host \
  -net nic,model=virtio \
  -net user${PORT_FORWARD_PARAMS} \
  -vga virtio \
  -display spice-app,gl=on \
  -device virtio-serial-pci \
  -device virtserialport,chardev=spicechannel0,name=com.redhat.spice.0 \
  -chardev spicevmc,id=spicechannel0,name=vdagent \
  -device ich9-usb-ehci1,id=usb \
  -device ich9-usb-uhci1,masterbus=usb.0,firstport=0,multifunction=on \
  -device ich9-usb-uhci2,masterbus=usb.0,firstport=2 \
  -device ich9-usb-uhci3,masterbus=usb.0,firstport=4 \
  -chardev spicevmc,name=usbredir,id=usbredirchardev1 \
  -device usb-redir,filter="${USB_FILTER}",chardev=usbredirchardev1,id=usbredirdev1 \
  -chardev spicevmc,name=usbredir,id=usbredirchardev2 \
  -device usb-redir,filter="${USB_FILTER}",chardev=usbredirchardev2,id=usbredirdev2 \
  -chardev spicevmc,name=usbredir,id=usbredirchardev3 \
  -device usb-redir,filter="${USB_FILTER}",chardev=usbredirchardev3,id=usbredirdev3 \
  -object iothread,id=iothread0 \
  -device virtio-scsi-pci,id=scsi0,iothread=iothread0,num_queues=4 \
  -drive id=hd-scsi0,file=${DISK_FILE},if=none,format=qcow2,discard=unmap,detect-zeroes=unmap,aio=threads,cache=none \
  -device scsi-hd,drive=hd-scsi0 \
  ${QEMU_EXTRA_PARAMETERS} \
  ${CMD_BOOT}
