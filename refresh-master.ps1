<#
Replace a master's golden snapshot after you have patched it.

Runs in two phases, because patching is interactive and takes as long as it
takes:

    .\refresh-master.ps1 -OS ubuntu             # powers the master on
    ...patch it, shut it down, close its tab in Workstation...
    .\refresh-master.ps1 -OS ubuntu -Snapshot   # swaps the snapshot

ALL CLONES MUST BE DELETED FIRST. A linked clone stores only the delta against
its parent snapshot, so replacing that snapshot leaves the clone pointing at
disk state that no longer exists - with no error at the time.
#>
param (
    [Parameter(Mandatory=$true)]
    [string]$OS,
    [switch]$Snapshot
)

. "$PSScriptRoot\vm-lib.ps1"

$master = Resolve-Master $OS
$vmx    = $master.Vmx

# --- safety: no clones may exist -----------------------------------------
$existing = @(Get-ChildItem $CloneRoot -Directory -EA 0)
if ($existing.Count -gt 0) {
    Write-Host "[!] Refusing to run: $($existing.Count) clone(s) still exist." -ForegroundColor Red
    Write-Host "    Replacing the snapshot would corrupt them. Delete these first:" -ForegroundColor Red
    $existing | ForEach-Object { Write-Host "      $($_.Name)" -ForegroundColor Red }
    exit 1
}

if (-not $Snapshot) {
    # --- phase 1: power on for patching ----------------------------------
    Write-Host "[-] Current snapshots on ${OS}:" -ForegroundColor Cyan
    & $VmRun listSnapshots "$vmx"

    Write-Host "[-] Powering on master..." -ForegroundColor Yellow
    & $VmRun start "$vmx"

    $update = switch ($master.Pkg) {
        'apt'   { 'sudo apt update && sudo apt full-upgrade -y && sudo apt autoremove -y' }
        'dnf'   { 'sudo dnf -y update' }
        default { '<your package manager update command>' }
    }

    Write-Host ""
    Write-Host "[+] Master is booting. Now:" -ForegroundColor Green
    Write-Host "      1. Log in and patch it:" -ForegroundColor DarkGray
    Write-Host "         $update" -ForegroundColor DarkGray
    Write-Host "      2. sudo shutdown -h now" -ForegroundColor DarkGray
    Write-Host "      3. Close the VM tab in Workstation (releases the file lock)" -ForegroundColor DarkGray
    Write-Host "      4. .\refresh-master.ps1 -OS $OS -Snapshot" -ForegroundColor DarkGray
    exit 0
}

# --- phase 2: replace the snapshot ---------------------------------------
if ((Get-RunningVmNames) -contains [IO.Path]::GetFileNameWithoutExtension($vmx)) {
    Write-Host "[!] Master is still running. Shut it down first." -ForegroundColor Red
    exit 1
}

Write-Host "[-] Before:" -ForegroundColor Cyan
& $VmRun listSnapshots "$vmx"

Write-Host "[-] Deleting old '$SnapshotName'..." -ForegroundColor Yellow
& $VmRun deleteSnapshot "$vmx" "$SnapshotName"
if ($LASTEXITCODE -ne 0) {
    Write-Host "    (none to delete - continuing)" -ForegroundColor DarkGray
}

Write-Host "[-] Taking new '$SnapshotName'..." -ForegroundColor Yellow
& $VmRun snapshot "$vmx" "$SnapshotName"
if ($LASTEXITCODE -ne 0) {
    Write-Host "[!] Snapshot failed. If this says 'file is already in use'," -ForegroundColor Red
    Write-Host "    close the VM tab in Workstation and re-run." -ForegroundColor Red
    exit 1
}

Write-Host "[-] After:" -ForegroundColor Cyan
& $VmRun listSnapshots "$vmx"
Write-Host "[+] $OS golden image refreshed." -ForegroundColor Green
