Function Extend-VMHardDisk {
    <#
        .Synopsis
         Extend virtual disk for a given VM.
        .DESCRIPTION
         This script will extend the virtual disk for a given VM. In some senses, it's just a wrapper to Set-HardDisk.
         The VM will be supplied as a parameter, and the script will first  check to see if there's a connection to any vCenter, and if not, prompt to 
         connect. 
         If it fails to connect, it will exit.
         
         Once connected, it willverify the VM exists, otherwise it will exit.
         Next, it will check if the VM has a snapshot, and if so, will inform of this and exit as the disk cannot be extended while a snapshot is present.

         It will then list the existing virtual disks, their sizes and their SCSI ID. 
         It will also list (if VMware Tools are running) the volumes and partitions at the OS level. This can be useful in trying to match a virtual disk 
         to a partition - though is not sufficient for all cases. 
         PowerCLI 12 and vSphere 7 offers more for this use case.

         At this point, the disk to be extended needs to be selected using the Name as has been reported, eg "Hard disk 3" and the new size (in GB)

         The script will check :
         1) If the new size is greater than 2TB - if so, an offline resize is needed (unless on vSphere 6.5 or later)
         2) If the new size is smaller than the current size - if so, it will inform of this, and exit, as we can't reduce the size of the disk.

         It will then resize the disk and once completed, display the new size of the specified hard disk. It will also display the last VIEvent for the VM, 
         which should reflect this change.

         The script will NOT resize the disk at the OS level.
        .PARAMETER VM
         The VM to perform the work on.
        .EXAMPLE
         Extend-VMDisk -vm TestVM1
        
        .NOTES
        Author          : Dave Lloyd
        Version         : 0.1

         #>

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $True)]
        [string]$VM
    )

    Clear-Host

    If ($Global:DefaultVIServers.name -eq $null) {
        Write-Host "Not currently connected to a vCenter." -ForegroundColor Green
        $vc = Read-Host "Please enter the IP or FQDN of a vCenter to connect to."

        Try {
            Connect-VIServer $vc -ErrorAction Stop
        }
        Catch {
            Write-Host "Unable to connect to $vc. Script will now exit." -ForegroundColor Green
            Break
        }
    }

    # First see if the VM exists, if not, we exit
    $targetVM = Get-VM $VM -ErrorAction SilentlyContinue
    If (-not $targetVM) {
        Write-Host "$VM was not found`n" -ForegroundColor Green
        Break
    }

    # Next see if the VM has a snapshot, if it does, we exit.
    $DoesItHaveASnapshot = $targetVM | Get-Snapshot
    If ($DoesItHaveASnapshot) {
        Write-Host "$TargetVM has a snapshot, so we can't extend the disk.`nExiting the script." -ForegroundColor Green
        Break
    }

    # Gather and present the list of disks
    $listOfDisks = $targetVM | Get-HardDisk |
    Select-Object Name, Filename, CapacityGB,
    @{N = 'SCSI ID'; E = {
            $hd = $_
            $ctrl = $hd.Parent.Extensiondata.Config.Hardware.Device | Where-Object { $_.Key -eq $hd.ExtensionData.ControllerKey }
            "$($ctrl.BusNumber):$($_.ExtensionData.UnitNumber)" }
    } # SCSI ID based on Luc Dekens response in https://code.vmware.com/forums/2530/vsphere-powercli#578118

    $OSDiskUsage = $TargetVM.Guest.Disks | Select-Object Path, `
        @{n = "Capacity (GB)"; E = { [math]::round($_.CapacityGB) } }, `
        @{n = "Free space (GB)"; E = { [math]::round($_.FreeSpaceGB) } }                         

    Write-Host "`n$VM has the following disks :" -ForegroundColor Green
    $listOfDisks | Out-Host

    If ($OSDiskUsage) {
        Write-Host "OS Disk usage :" -ForegroundColor Green
        $OSDiskUsage | Out-Host
    }

    $TargetDisk = Read-Host "Type the name of the disk you wish to extend." 
    $TestDiskIsValid = $listOfDisks | where-object { $_.Name -eq $TargetDisk } -ErrorAction SilentlyContinue
    If (-not $TestDiskIsValid) {
        Write-Host "$TargetDisk not found" -ForegroundColor Green
        Break
    }

    [decimal]$newDiskSize = Read-Host "Enter the new size for the hard disk (in GB)" 
    # Now check, disks above 2TB in size need 6.5 or later to hot extend, otherwise the VM will need to be shutdown first.
    # And is the new size is smaller than the existing, we can't do it either.
    [decimal]$DiskLimit = 2000
    $vcVersion = $Global:DefaultVIServers.version
    If ($newDiskSize -gt $DiskLimit -AND $vcVersion -lt "6.5.0") {
        Write-Host "New size exceeds 2TB, and vSphere is older than 6.5, so the VM will need to be shutdown first.`nExiting the script.`n" -ForegroundColor Green
        Break
        # TODO : bly actually check if Tools are running, and if so, offer the option at least to shutdown and make the change.
    } elseif ($newDiskSize -lt [decimal]$TestDiskIsValid.capacityGB) {
        Write-Host "New size specified is less than the current size, and we can't shrink the disk.`nExiting the script.`n" -ForegroundColor Green
        Break
    }

    # Ok, so looks like we should be able to actually go ahead with the resize.
    Write-Host "`nResizing the disk." -ForegroundColor Green
    $targetVM | Get-HardDisk -Name $TargetDisk | Set-HardDisk -CapacityGB $newDiskSize -Confirm:$false | Out-Null
    # Would like to include the event log to show it - kind of hoping that it will always be the latest event ...
    $EventMsg = Get-VIEvent -Entity $TargetVM -MaxSamples 1 | Select-Object CreatedTime, Username, FullFormattedMessage | Format-Table -Wrap

    # Retrieve the properties again 
    $TargetVM = Get-VM $VM
    $newDisk = $TargetVM | Get-HardDisk -Name $TargetDisk | Select-Object Name, CapacityGB 
    Write-Host "`nNew size is : " -ForegroundColor Green
    $newDisk | Out-Host

    Write-Host "`nMost recent event from the logs." -ForegroundColor Green
    $EventMsg | Out-Host

    Write-Host "Work complete, script ending." -ForegroundColor Green
} # end function


