# ---------------------------------------------------------------------------
# Local configuration. Copy this file to vm-config.ps1 and edit it.
# vm-config.ps1 is gitignored - your paths stay on your machine.
#
#     Copy-Item vm-config.example.ps1 vm-config.ps1
#
# ---------------------------------------------------------------------------

# Path to vmrun.exe (ships with VMware Workstation)
$VmRun = "C:\Program Files (x86)\VMware\VMware Workstation\vmrun.exe"

# Where your master images live, and where clones get created
$BaseDir   = "C:\vms"
$CloneRoot = "$BaseDir\clones"

# Name of the snapshot on each master that clones are linked from
$SnapshotName = "Golden_Image"

# Your master images. Add, remove or rename entries freely - the scripts read
# this table, nothing is hardcoded.
#
#   Key   - short name you pass to -OS (e.g. .\start-vm.ps1 -OS ubuntu)
#   Vmx   - full path to the master's .vmx
#   User  - login shown in the ssh hint after a clone boots
#   Pkg   - 'apt' or 'dnf'; only used to print the right update command
#
$Masters = [ordered]@{
    'ubuntu' = @{
        Vmx  = "$BaseDir\ubuntu_master\ubuntu_master.vmx"
        User = "youruser"
        Pkg  = "apt"
    }
    'rhel10' = @{
        Vmx  = "$BaseDir\rhel10_master\rhel10_master.vmx"
        User = "root"
        Pkg  = "dnf"
    }
    'rhel9' = @{
        Vmx  = "$BaseDir\rhel9_master\rhel9_master.vmx"
        User = "root"
        Pkg  = "dnf"
    }
}
