<#
List every clone with its status, IP, size and creation time.

    .\list-vms.ps1
    .\list-vms.ps1 -NoIP     # skip the IP lookup (faster)

Emits objects, so it pipes:

    .\list-vms.ps1 | Where-Object Status -eq 'Stopped'
    .\list-vms.ps1 | Where-Object Status -eq 'Stopped' |
        ForEach-Object { .\delete-vm.ps1 -Name $_.Name -Force }
#>
param(
    [switch]$NoIP
)

. "$PSScriptRoot\vm-lib.ps1"

if (-not (Test-Path $CloneRoot)) {
    Write-Error "No clones directory at $CloneRoot"
    exit 1
}

Get-VmClones -NoIP:$NoIP
