#!/bin/bash
FILE_MSDM="msdm.acpi.bin"
FILE_SLIC="slic.acpi.bin"
FILE_BIOS="smbios.bin"

if [[ ! -e "${FILE_MSDM}" ]]; then
    cat /sys/firmware/acpi/tables/MSDM > "${FILE_MSDM}"
else
    echo "File '${FILE_MSDM}' already exists."
fi

if [[ ! -e "${FILE_SLIC}" ]]; then
    cat /sys/firmware/acpi/tables/SLIC > "${FILE_SLIC}"
else
    echo "File '${FILE_SLIC}' already exists."
fi

if [[ ! -e "${FILE_BIOS}" ]]; then
     dmidecode -t 1 -u | grep $'^\t\t[^"]' | xargs -n1 | perl -lne 'printf "%c", hex($_)' > "${FILE_BIOS}"
else
    echo "File '${FILE_BIOS}' already exists."
fi
