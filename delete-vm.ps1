<#
Stop, unregister and delete a clone, then remove its folder.

    .\delete-vm.ps1                 # interactive picker
    .\delete-vm.ps1 -Name test01
    .\delete-vm.ps1 -Name test01 -Force   # skip the typed confirmation
#>
param (
    [string]$Name,
    [switch]$Force
)

. "$PSScriptRoot\vm-lib.ps1"

$clones = @(Get-VmClones -NoIP)

# --- pick a VM ----------------------------------------------------------
if (-not $Name) {
    if ($clones.Count -eq 0) {
        Write-Host "[!] No clones found in $CloneRoot" -ForegroundColor Yellow
        exit
    }

    Write-Host "`nClones:" -ForegroundColor Cyan
    Show-VmClones -Clones $clones -Numbered

    $sel = Read-Host "`nDelete which? (1-$($clones.Count), or Enter to cancel)"
    if ([string]::IsNullOrWhiteSpace($sel)) { Write-Host "Cancelled."; exit }
    if ($sel -notmatch '^\d+$' -or [int]$sel -lt 1 -or [int]$sel -gt $clones.Count) {
        Write-Host "[!] Invalid selection." -ForegroundColor Red
        exit 1
    }
    $Name = $clones[[int]$sel - 1].Name
}

$cloneFolder = "$CloneRoot\$Name"
$cloneVmx    = "$cloneFolder\$Name.vmx"

if (-not (Test-Path $cloneFolder)) {
    Write-Host "[!] Error: folder for VM '$Name' not found at $cloneFolder" -ForegroundColor Red
    exit 1
}

# --- confirm ------------------------------------------------------------
if (-not $Force) {
    $isRunning = (Get-RunningVmNames) -contains $Name
    $warn = if ($isRunning) { ' (currently RUNNING - will be hard-stopped)' } else { '' }
    Write-Host "`nAbout to permanently delete '$Name'$warn" -ForegroundColor Yellow
    if ((Read-Host "Type the VM name to confirm") -ne $Name) {
        Write-Host "Cancelled."
        exit
    }
}

# --- delete -------------------------------------------------------------
Write-Host "[-] Attempting to stop '$Name'..." -ForegroundColor Yellow
& $VmRun stop "$cloneVmx" hard 2>$null

Write-Host "[-] Unregistering and deleting '$Name' from disk..." -ForegroundColor Yellow
if (Test-Path $cloneVmx) {
    & $VmRun deleteVM "$cloneVmx"
} else {
    Write-Host "[!] No .vmx at $cloneVmx - orphaned folder, cleaning up only." -ForegroundColor Yellow
}

if (Test-Path $cloneFolder) {
    Remove-Item -Path $cloneFolder -Recurse -Force
    Write-Host "[+] Deleted '$Name' and cleaned up the folder." -ForegroundColor Green
} else {
    Write-Host "[+] '$Name' removed by VMware; folder already gone." -ForegroundColor Green
}
