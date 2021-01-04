#!/bin/bash

# Just a copy and paste from Maagu Karuri respositry
# https://gitlab.com/Karuri/vfio/-/blob/master/check-iommu.sh

shopt -s nullglob
for g in /sys/kernel/iommu_groups/*; do
    echo "IOMMU Group ${g##*/}:"
    for d in $g/devices/*; do
        echo -e "\t$(lspci -nns ${d##*/})"
    done;
done;
