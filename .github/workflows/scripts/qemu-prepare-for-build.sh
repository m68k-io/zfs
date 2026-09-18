#!/usr/bin/env bash

# Helper script to run after installing dependencies.  This brings the VM back
# up and copies over the zfs source directory.
echo "Build modules in QEMU machine"
sudo virsh start openzfs

# Capture vm0's serial console the way qemu-5-setup.sh does for the
# testing VMs.  Nothing records the build VM's boot today, so a slow or
# stalled boot here is invisible.  Timestamp each line: the point is to
# see where the time goes, and the console has no clock of its own.
#
# Detach it from this step's stdout and stderr.  A background process
# that still holds them keeps the step open until it exits, and this one
# only exits when the VM powers off and takes the pty with it -- which
# would leave qemu already gone when the next step looks for it.
read "pty" <<< $(sudo virsh ttyconsole openzfs)
mkdir -p /var/tmp/test_results/vm0
touch /var/tmp/test_results/vm0/console.txt
sudo nohup bash -c "while IFS= read -r l; do \
  printf '%s %s\\n' \"\$(date -u +%H:%M:%S)\" \"\$l\"; \
done < $pty > /var/tmp/test_results/vm0/console.txt" >/dev/null 2>&1 &

.github/workflows/scripts/qemu-wait-for-vm.sh vm0
rsync -ar $HOME/work/zfs/zfs zfs@vm0:./
