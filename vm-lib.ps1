# ---------------------------------------------------------------------------
# Shared config loader and helpers. Dot-sourced by the other scripts:
#     . "$PSScriptRoot\vm-lib.ps1"
# Not meant to be run directly.
# ---------------------------------------------------------------------------

$configPath = Join-Path $PSScriptRoot 'vm-config.ps1'
if (-not (Test-Path $configPath)) {
    Write-Host "[!] Missing config: $configPath" -ForegroundColor Red
    Write-Host "    Create it with:" -ForegroundColor Yellow
    Write-Host "      Copy-Item `"$PSScriptRoot\vm-config.example.ps1`" `"$configPath`"" -ForegroundColor DarkGray
    Write-Host "    then edit the paths inside." -ForegroundColor Yellow
    exit 1
}
. $configPath

foreach ($required in 'VmRun', 'BaseDir', 'CloneRoot', 'SnapshotName', 'Masters') {
    if (-not (Get-Variable -Name $required -Scope Script -EA 0) -and
        -not (Get-Variable -Name $required -Scope Global -EA 0) -and
        -not (Get-Variable -Name $required -EA 0)) {
        Write-Host "[!] vm-config.ps1 does not define `$$required" -ForegroundColor Red
        exit 1
    }
}

if (-not (Test-Path $VmRun)) {
    Write-Host "[!] vmrun.exe not found at: $VmRun" -ForegroundColor Red
    Write-Host "    Fix `$VmRun in vm-config.ps1" -ForegroundColor Yellow
    exit 1
}


function Get-RunningVmNames {
    <# Leaf names of every powered-on VM. Matching on the name rather than the
       full path keeps this working when the VM directory is a symlink or
       junction, where vmrun may report the resolved target path. #>
    @(& $VmRun list |
        Where-Object { $_ -like '*.vmx' } |
        ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_.Trim()) })
}


function Get-VmClones {
    <# One object per clone directory. -NoIP skips the per-VM IP lookup. #>
    param([switch]$NoIP)

    if (-not (Test-Path $CloneRoot)) { return }
    $running = Get-RunningVmNames

    foreach ($dir in Get-ChildItem $CloneRoot -Directory | Sort-Object Name) {

        $vmx    = Join-Path $dir.FullName "$($dir.Name).vmx"
        $sizeGB = [math]::Round((Get-ChildItem $dir.FullName -Recurse -File -EA 0 |
                    Measure-Object Length -Sum).Sum / 1GB, 2)

        if (-not (Test-Path $vmx)) {
            [PSCustomObject]@{
                Name = $dir.Name; Status = 'ORPHAN'; IP = ''; Guest = ''
                SizeGB = $sizeGB; Created = $dir.CreationTime
            }
            continue
        }

        $isRunning = $running -contains $dir.Name

        $ip = ''
        if ($isRunning -and -not $NoIP) {
            $out = (& $VmRun getGuestIPAddress "$vmx" 2>$null) -join ' '
            if ($out -match '\b\d{1,3}(\.\d{1,3}){3}\b' -and $Matches[0] -ne '0.0.0.0') {
                $ip = $Matches[0]
            } else {
                $ip = '(no tools yet)'
            }
        }

        $guest = (Select-String -Path $vmx -Pattern '^guestOS\s*=' -EA 0 |
                  Select-Object -First 1).Line -replace '.*"(.*)".*', '$1'

        [PSCustomObject]@{
            Name    = $dir.Name
            Status  = if ($isRunning) { 'Running' } else { 'Stopped' }
            IP      = $ip
            Guest   = $guest
            SizeGB  = $sizeGB
            Created = $dir.CreationTime
        }
    }
}


function Show-VmClones {
    <# Colored console listing. -Numbered prefixes [1] [2] ... for pickers. #>
    param(
        [AllowEmptyCollection()][array]$Clones,
        [switch]$Numbered
    )

    if ($null -eq $Clones -or $Clones.Count -eq 0) {
        Write-Host "  (none)" -ForegroundColor DarkGray
        return
    }

    for ($i = 0; $i -lt $Clones.Count; $i++) {
        $c      = $Clones[$i]
        $prefix = if ($Numbered) { "  [{0}] " -f ($i + 1) } else { "  " }
        $color  = switch ($c.Status) {
            'Running' { 'Green' }
            'ORPHAN'  { 'Yellow' }
            default   { 'DarkGray' }
        }
        Write-Host ("{0}{1,-20} {2,-8} {3} GB" -f $prefix, $c.Name, $c.Status, $c.SizeGB) `
                   -ForegroundColor $color
    }
}


function Resolve-Master {
    <# Look up a master by its config key, or exit with the valid keys. #>
    param([string]$Key)

    if (-not $Masters.Contains($Key)) {
        Write-Host "[!] Unknown OS '$Key'. Defined in vm-config.ps1:" -ForegroundColor Red
        $Masters.Keys | ForEach-Object { Write-Host "      $_" -ForegroundColor DarkGray }
        exit 1
    }

    $m = $Masters[$Key]
    if (-not (Test-Path $m.Vmx)) {
        Write-Host "[!] Master vmx not found: $($m.Vmx)" -ForegroundColor Red
        exit 1
    }
    return $m
}
