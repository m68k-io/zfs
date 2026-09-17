#!/usr/bin/env bash

# Helper script to run after installing dependencies.  This brings the VM back
# up and copies over the zfs source directory.
echo "Build modules in QEMU machine"
sudo virsh start openzfs

# Capture vm0's serial console the way qemu-5-setup.sh does for the
# testing VMs.  Nothing records the build VM's boot today, so a slow or
# stalled boot here is invisible.
read "pty" <<< $(sudo virsh ttyconsole openzfs)
mkdir -p /var/tmp/test_results/vm0
touch /var/tmp/test_results/vm0/console.txt
sudo nohup bash -c "cat $pty > /var/tmp/test_results/vm0/console.txt" &

.github/workflows/scripts/qemu-wait-for-vm.sh vm0
rsync -ar $HOME/work/zfs/zfs zfs@vm0:./
