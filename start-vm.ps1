<#
Create a linked clone from a master image and boot it.

    .\start-vm.ps1                          # interactive
    .\start-vm.ps1 -OS ubuntu -Name test01  # non-interactive

The clone's hostname is injected via guestinfo.hostname and picked up at boot
by set-guest-hostname.service inside the guest. See guest/README in this repo.
#>
param (
    [string]$OS,
    [string]$Name
)

. "$PSScriptRoot\vm-lib.ps1"

# --- show what already exists -------------------------------------------
Write-Host "`nExisting clones:" -ForegroundColor Cyan
Show-VmClones -Clones @(Get-VmClones -NoIP)

# --- pick the master ----------------------------------------------------
if (-not $OS) {
    $keys = @($Masters.Keys)
    Write-Host "`nAvailable masters:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $keys.Count; $i++) {
        $missing = if (Test-Path $Masters[$keys[$i]].Vmx) { '' } else { '   <-- vmx not found' }
        Write-Host ("  [{0}] {1}{2}" -f ($i + 1), $keys[$i], $missing)
    }
    do {
        $sel = Read-Host "Choose OS (1-$($keys.Count))"
    } until ($sel -match '^\d+$' -and [int]$sel -ge 1 -and [int]$sel -le $keys.Count)
    $OS = $keys[[int]$sel - 1]
}
$master = Resolve-Master $OS

# --- pick the name ------------------------------------------------------
if (-not $Name) {
    $n = 1
    while (Test-Path "$CloneRoot\$OS$('{0:d2}' -f $n)") { $n++ }
    $default = "$OS$('{0:d2}' -f $n)"
    $Name = Read-Host "New VM name [$default]"
    if ([string]::IsNullOrWhiteSpace($Name)) { $Name = $default }
}

if ($Name -notmatch '^[A-Za-z0-9][A-Za-z0-9-]*$') {
    Write-Host "[!] '$Name' is not a valid hostname (letters, digits, hyphens)." -ForegroundColor Red
    exit 1
}

$cloneDir = "$CloneRoot\$Name"
$cloneVmx = "$cloneDir\$Name.vmx"

if (Test-Path $cloneVmx) {
    Write-Host "[!] '$Name' already exists. Delete it first, or pick another name." -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $cloneDir)) { New-Item -ItemType Directory -Path $cloneDir | Out-Null }

# --- clone and boot -----------------------------------------------------
Write-Host "`n[-] Creating linked clone '$Name' from $OS..." -ForegroundColor Cyan
& $VmRun clone "$($master.Vmx)" "$cloneVmx" linked -snapshot="$SnapshotName" "$Name"
if ($LASTEXITCODE -ne 0) {
    Write-Host "[!] Clone failed - check that '$SnapshotName' exists on $OS." -ForegroundColor Red
    Write-Host "    & `$VmRun listSnapshots `"$($master.Vmx)`"" -ForegroundColor DarkGray
    Remove-Item $cloneDir -Recurse -Force -EA 0
    exit 1
}

# Consumed at boot by set-guest-hostname.service inside the guest
Add-Content -Path $cloneVmx -Value "guestinfo.hostname = `"$Name`""

Write-Host "[-] Powering on..." -ForegroundColor Cyan
& $VmRun start "$cloneVmx"

Write-Host "[-] Waiting for VMware Tools to report an IP..." -ForegroundColor Yellow
Start-Sleep -Seconds 10

$maxRetries = 20
for ($attempt = 0; $attempt -lt $maxRetries; $attempt++) {
    $out = (& $VmRun getGuestIPAddress "$cloneVmx" 2>$null) -join ' '
    if ($out -match '\b\d{1,3}(\.\d{1,3}){3}\b' -and $Matches[0] -ne '0.0.0.0') {
        Write-Host "`n[+] Success! $Name is up at $($Matches[0])" -ForegroundColor Green
        Write-Host "    ssh $($master.User)@$($Matches[0])" -ForegroundColor DarkGray
        return
    }
    Write-Host "." -NoNewline
    Start-Sleep -Seconds 3
}

Write-Host "`n[!] Timed out after $($maxRetries * 3)s. VM is running but Tools is not reporting an IP." -ForegroundColor Red
