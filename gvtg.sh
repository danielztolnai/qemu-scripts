#!/bin/bash
GVT_DOM="0000:00"
GVT_PCI="0000:00:02.0"
GVT_TYPE="i915-GVTg_V5_8"

function gvt_find() {
    GVT_DIR="/sys/bus/pci/devices/${GVT_PCI}"
    if GVT_GUID=$(ls "${GVT_DIR}" | grep -s -m 1 -P '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$'); then
        GVT_PATH="${GVT_DIR}/${GVT_GUID}"
        echo "${GVT_PATH}"
        return 0
    else
        return 1
    fi
}

case "${1}" in
    create)
        if ! gvt_find; then
            GVT_GUID="$(uuidgen)"
            echo "${GVT_GUID}" > "/sys/devices/pci${GVT_DOM}/${GVT_PCI}/mdev_supported_types/${GVT_TYPE}/create"
            gvt_find
        fi
        exit
        ;;

    remove)
        if GVT_PATH="$(gvt_find)"; then
            echo 1 > "${GVT_PATH}/remove"
            exit 0
        else
            exit 1
        fi
        ;;

    status)
        gvt_find
        exit
        ;;

    *)
        echo "Usage: ${0} {create|remove|status}" >&2
        exit 1
        ;;
esac

exit 2
