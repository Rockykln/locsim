# Create an RPPairing file over USB on Windows.
# Needs Apple's USB driver from the "Apple Devices" app (Microsoft Store) or iTunes.
# Usage: powershell -ExecutionPolicy Bypass -File tools\make-pairing.ps1 [-Hostname locsim] [-Out rppairing.plist] [-Udid UDID]
param(
    [string]$Hostname = "locsim",
    [string]$Out = "rppairing.plist",
    [string]$Udid = ""
)
$ErrorActionPreference = "Stop"

$Version = "v0.1.68"
$Sha256 = "1c15e627652db1bc7c68f3d32675be07238b75282b510cd5828e9f4bec692a2f"
$Dir = Join-Path $env:LOCALAPPDATA "locsim\idevice-tools-windows-$Version"
$Bin = Join-Path $Dir "idevice-tools.exe"
$List = Join-Path $Dir "idevice_id.exe"
$Marker = Join-Path $Dir ".verified"

# Native tools resolve relative paths against the process directory, not the PowerShell location.
$Out = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Out)

# The build is x86-64; Windows 11 on ARM runs it emulated, Windows 10 on ARM cannot.
$Arch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
if ($Arch -eq "ARM64" -and [Environment]::OSVersion.Version.Build -lt 22000) {
    Write-Host "idevice-tools needs Windows 11 on ARM computers (Windows 10 cannot run x64 programs there)."
    exit 1
}

# -LiteralPath everywhere: folders like "Projects [old]" would otherwise be read as wildcards.
# An empty marker reads as $null; the [string] cast keeps .Trim() from throwing.
$Verified = (Test-Path -LiteralPath $Marker) -and (([string](Get-Content -LiteralPath $Marker -Raw)).Trim() -eq "$Version $Sha256")
if (-not ($Verified -and (Test-Path -LiteralPath $Bin) -and (Test-Path -LiteralPath $List))) {
    if (Test-Path -LiteralPath $Dir) { Remove-Item -LiteralPath $Dir -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $Dir | Out-Null
    $Zip = Join-Path $Dir "idevice-tools-windows-$Version.zip"
    if ($PSVersionTable.PSVersion.Major -lt 6) {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    }
    $OldProgress = $ProgressPreference
    $ProgressPreference = "SilentlyContinue"
    try {
        Invoke-WebRequest -UseBasicParsing -OutFile $Zip `
            -Uri "https://github.com/jkcoxson/idevice/releases/download/$Version/idevice-tools-windows-$Version.zip"
        $Actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $Zip).Hash.ToLower()
        if ($Actual -ne $Sha256) {
            Remove-Item -LiteralPath $Zip
            throw "Checksum mismatch for idevice-tools: $Actual"
        }
        Expand-Archive -LiteralPath $Zip -DestinationPath $Dir -Force
    } finally {
        $ProgressPreference = $OldProgress
    }
    Remove-Item -LiteralPath $Zip
    Set-Content -LiteralPath $Marker -Value "$Version $Sha256"
}

function Write-Checklist {
    Write-Host "Check:"
    Write-Host "  - the iPhone is unlocked and connected by USB"
    Write-Host "  - `"Trust This Computer`" was accepted on the iPhone"
    Write-Host "  - Developer Mode is on (Settings > Privacy & Security)"
    Write-Host "  - only one iPhone is connected, or pass -Udid"
    Write-Host "  - the Apple Devices app (Microsoft Store) or iTunes is installed"
}

# Native tools write to stderr; with "Stop" Windows PowerShell 5.1 would turn that into an exception.
$ErrorActionPreference = "Continue"

$UdidArgs = @()
if ($Udid) {
    $UdidArgs = @("--udid", $Udid)
} else {
    $Devices = & $List 2>$null | ForEach-Object { "$_" }
    if ($LASTEXITCODE -eq 0) {
        $Usb = @()
        $IsUsb = $false
        foreach ($Line in $Devices) {
            if ($Line -match "connection_type:") { $IsUsb = $Line -match "connection_type: Usb," }
            if ($IsUsb -and $Line -match 'udid: "([^"]+)"') { $Usb += $Matches[1] }
        }
        $Usb = @($Usb | Sort-Object -Unique)
        if ($Usb.Count -gt 1) {
            Write-Host "More than one iPhone is connected over USB:"
            $Usb | ForEach-Object { Write-Host "  $_" }
            Write-Host "Connect only one, or pick one with:"
            Write-Host "  powershell -ExecutionPolicy Bypass -File make-pairing.ps1 -Udid <UDID>"
            exit 1
        }
    }
}

Write-Host "Make sure the iPhone is connected by USB, unlocked and trusts this computer."
if (Test-Path -LiteralPath $Out) { Remove-Item -LiteralPath $Out -Force }
$Kept = $false
try {
    $PairLog = & $Bin @UdidArgs remotepairing_lockdown pair $Hostname $Out 2>&1 | ForEach-Object { "$_" }
    $Written = (Test-Path -LiteralPath $Out) -and ((Get-Item -LiteralPath $Out).Length -gt 0)
    if ($LASTEXITCODE -ne 0 -or -not $Written) {
        Write-Host "Pairing failed:"
        if ($PairLog) { $PairLog | ForEach-Object { Write-Host $_ } } else { Write-Host "no output from idevice-tools" }
        Write-Host ""
        Write-Checklist
        exit 1
    }

    # Only the current user may read the file.
    # By SID, which also works for domain and Entra ID accounts; Modify keeps the file deletable.
    $Sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    icacls "$Out" /inheritance:r /grant:r "*$($Sid):(M)" | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Host "Could not restrict access to $Out. Delete it after the import." }

    Write-Host ""
    Write-Host "Hostname: $Hostname (must match LocSim > Settings > Hostname)"

    # LocSim picks the file up from its Documents folder and removes it there.
    # The tool can report errors on stderr with exit code 0, so stderr counts as failure.
    $AfcResult = & $Bin @UdidArgs afc --documents com.rockykln.locsim upload $Out /Documents/rppairing.plist 2>&1
    $AfcCode = $LASTEXITCODE
    $AfcErr = @($AfcResult | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object { "$_" })
    if ($AfcCode -eq 0 -and $AfcErr.Count -eq 0) {
        Write-Host "Copied into LocSim and removed here. Open LocSim to finish."
    } else {
        $Kept = $true
        Write-Host "Could not copy the file into LocSim:"
        if ($AfcErr.Count -gt 0) { $AfcErr | ForEach-Object { Write-Host $_ } } else { Write-Host "idevice-tools exited with code $AfcCode" }
        Write-Host "Is LocSim installed and the iPhone unlocked?"
        Write-Host ""
        Write-Host "The pairing file is at: $Out"
        Write-Host "Move it to the device, for example with the Apple Devices app (Files tab > LocSim)."
        Write-Host "Avoid cloud storage: the file grants access to the device. Delete it here afterwards."
        exit 3
    }
} finally {
    # A pairing file from a failed or interrupted run must not stay on the disk.
    if (-not $Kept -and (Test-Path -LiteralPath $Out)) { Remove-Item -LiteralPath $Out -Force }
}
