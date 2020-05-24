# Extend-VMHardDisk.ps1

Basic script to resize a given VMDK on a VM. Of course this is easy to do in the GUI, or even just with the Set-HardDisk cmdlet, but this just adds a few checks into the mix. Plus it's also just a good exercise to try and write a script.

The script checks when run if the session is conneted to a vCenter, and if not, prompts to do so.
It then checks to see if the selected VM exists, and if it does, if it has an existing snapshot. If the VM doesn't exist, or it has a snapshot, then it exits.

Next, it presents the HardDisks as seen from the VMware perspective, and also (if VMwareTools are running), the volumes/partitions and their usage at the OS level.
The specific harddisk is selected, and the selection verified. If the target size is greater than 2TB, and the vCenter is earlier than 6.5, then it will inform that the VM needs to be shutdown in order to make the change.

If the target size is smaller than the existing size, then the script will exit, as it can't reduce the size of a VMDK.

If it looks like the target size is ok, then it will performn the resizing, and then retrieve the new size of the disk from the VMware perspective, as well as the last event from the VIEvents (hopefully this will be the event showing the extension - don't currently appear to be able to search directly for the Event Type ID : vim.event.VmReconfiguredEvent)

## Limitations
Currenly the script doesn't include the ability to :
1) Offer to shutdown the VM and extend the disk, if the new size exceeds 2TB and vSphere version is less than 6.5
2) Extend the disk at the OS level.
