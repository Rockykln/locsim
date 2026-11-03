# Create an RPPairing file over USB on Windows.
# Needs Apple's USB driver from the "Apple Devices" app (Microsoft Store) or iTunes.
# Usage: powershell -ExecutionPolicy Bypass -File tools\make-pairing.ps1 [-Hostname locsim] [-Out rppairing.plist]
param(
    [string]$Hostname = "locsim",
    [string]$Out = "rppairing.plist"
)
$ErrorActionPreference = "Stop"

$Version = "v0.1.68"
$Sha256 = "1c15e627652db1bc7c68f3d32675be07238b75282b510cd5828e9f4bec692a2f"
$Dir = Join-Path $PSScriptRoot "bin\windows-$Version"
$Bin = Join-Path $Dir "idevice-tools.exe"

if (-not (Test-Path $Bin)) {
    New-Item -ItemType Directory -Force -Path $Dir | Out-Null
    $Zip = Join-Path $Dir "idevice-tools-windows-$Version.zip"
    Invoke-WebRequest -UseBasicParsing -OutFile $Zip `
        -Uri "https://github.com/jkcoxson/idevice/releases/download/$Version/idevice-tools-windows-$Version.zip"
    $Actual = (Get-FileHash -Algorithm SHA256 $Zip).Hash.ToLower()
    if ($Actual -ne $Sha256) {
        Remove-Item $Zip
        throw "Checksum mismatch for idevice-tools: $Actual"
    }
    Expand-Archive -Path $Zip -DestinationPath $Dir -Force
}

Write-Host "iPhone: connected via USB, unlocked, trusted."
& $Bin remotepairing_lockdown pair $Hostname $Out
if ($LASTEXITCODE -ne 0) { throw "Pairing failed (exit code $LASTEXITCODE)" }

# Only the current user may read the file.
icacls $Out /inheritance:r /grant:r "$($env:USERNAME):(R,W)" | Out-Null

Write-Host ""
Write-Host "Hostname: $Hostname (must match LocSim > Settings > Hostname)"

# LocSim picks the file up from its Documents folder and removes it there.
# Errors of this step only lead to the manual way, so they must not stop the script.
$ErrorActionPreference = "Continue"
& $Bin afc --documents com.rockykln.locsim upload $Out /Documents/rppairing.plist *> $null
if ($LASTEXITCODE -eq 0) {
    Remove-Item $Out
    Write-Host "Copied into LocSim and removed here. Open LocSim to finish."
} else {
    Write-Host "Could not copy the file into LocSim. Is it installed on this iPhone?"
    Write-Host "Move $Out to the device, for example with the Apple Devices app (Files tab > LocSim)."
    Write-Host "Avoid cloud storage: the file grants access to the device. Delete it here afterwards."
}
