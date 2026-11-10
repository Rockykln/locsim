# Create an RPPairing file over USB on Windows.
# Needs Apple's USB driver from the "Apple Devices" app (Microsoft Store) or iTunes.
# Usage:
#   curl.exe -fLO <URL of this script>
#   powershell -NoProfile -ExecutionPolicy Bypass -File make-pairing.ps1 [-Hostname locsim] [-Out path\rppairing.plist] [-Udid UDID]
# Without -Out the file is written to %LOCALAPPDATA%\locsim\pairing.
param(
    [string]$Hostname = "locsim",
    [string]$Out = "",
    [string]$Udid = ""
)
$ErrorActionPreference = "Stop"

if (-not [Environment]::Is64BitOperatingSystem) {
    Write-Host "This is 32-bit Windows. idevice-tools needs 64-bit Windows, so the pairing file cannot be created on this computer."
    exit 1
}

# The build is x86-64; Windows 11 on ARM runs it emulated, Windows 10 on ARM cannot.
$Arch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
if ($Arch -eq "ARM64" -and [Environment]::OSVersion.Version.Build -lt 22000) {
    Write-Host "idevice-tools needs Windows 11 on ARM computers (Windows 10 cannot run x64 programs there)."
    exit 1
}

$Version = "v0.1.68"
$Sha256 = "1c15e627652db1bc7c68f3d32675be07238b75282b510cd5828e9f4bec692a2f"
$Dir = Join-Path $env:LOCALAPPDATA "locsim\idevice-tools-windows-$Version"
$Bin = Join-Path $Dir "idevice-tools.exe"
$List = Join-Path $Dir "idevice_id.exe"
$Marker = Join-Path $Dir ".verified"
$Sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value

if ($Out) {
    # Native tools resolve relative paths against the process directory, not the PowerShell location.
    $Out = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Out)
    $PairDir = $null
} else {
    $PairDir = Join-Path $env:LOCALAPPDATA "locsim\pairing"
    $Out = Join-Path $PairDir "rppairing.plist"
}

function Write-Checklist {
    Write-Host "Check:"
    Write-Host "  - the iPhone or iPad is unlocked and connected by USB"
    Write-Host "  - `"Trust This Computer`" was accepted on the device"
    Write-Host "  - Developer Mode is on (Settings > Privacy & Security)"
    Write-Host "  - only one device is connected, or pass -Udid"
    Write-Host "  - the Apple Devices app (Microsoft Store) or iTunes is installed"
}

function Write-AntivirusHint {
    Write-Host "If idevice-tools.exe or idevice_id.exe is missing, antivirus software may have removed it."
    Write-Host "Look in Windows Security > Virus & threat protection > Protection history."
}

function Test-Usbmuxd {
    $Client = New-Object System.Net.Sockets.TcpClient
    try {
        $Task = $Client.ConnectAsync("127.0.0.1", 27015)
        return ($Task.Wait(3000) -and $Client.Connected)
    } catch {
        return $false
    } finally {
        $Client.Close()
    }
}

# UTF-8 so device names and tool output show correctly; restored at the end.
$OldEncoding = $null
try {
    $OldEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
} catch { }

$Started = $false
$Kept = $false
$OldRustLog = $env:RUST_LOG
try {
    if (-not $env:USBMUXD_SOCKET_ADDRESS -and -not (Test-Usbmuxd)) {
        Write-Host "The Apple USB service (usbmuxd) does not answer on 127.0.0.1:27015."
        Write-Host "Install the Apple Devices app from the Microsoft Store, or iTunes, then run this script again."
        Write-Host "If one of them is installed, connect the device and open the app once, or restart the computer."
        exit 1
    }

    # -LiteralPath everywhere: folders like "Projects [old]" would otherwise be read as wildcards.
    # An empty marker reads as $null; the [string] cast keeps .Trim() from throwing.
    $Verified = (Test-Path -LiteralPath $Marker) -and (([string](Get-Content -LiteralPath $Marker -Raw)).Trim() -eq "$Version $Sha256")
    if (-not ($Verified -and (Test-Path -LiteralPath $Bin) -and (Test-Path -LiteralPath $List))) {
        if (Test-Path -LiteralPath $Dir) { Remove-Item -LiteralPath $Dir -Recurse -Force }
        New-Item -ItemType Directory -Force -Path $Dir | Out-Null
        $Zip = Join-Path $Dir "idevice-tools-windows-$Version.zip"
        $Url = "https://github.com/jkcoxson/idevice/releases/download/$Version/idevice-tools-windows-$Version.zip"
        if ($PSVersionTable.PSVersion.Major -lt 6) {
            [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
            # Lets proxies that need the Windows login work.
            if ([Net.WebRequest]::DefaultWebProxy) {
                [Net.WebRequest]::DefaultWebProxy.Credentials = [Net.CredentialCache]::DefaultNetworkCredentials
            }
        }
        $OldProgress = $ProgressPreference
        $ProgressPreference = "SilentlyContinue"
        try {
            try {
                Invoke-WebRequest -UseBasicParsing -OutFile $Zip -Uri $Url
            } catch {
                Write-Host "Could not download idevice-tools:"
                Write-Host "  $($_.Exception.Message)"
                Write-Host "URL: $Url"
                Write-Host "Check the internet connection. Behind a proxy or firewall, github.com and"
                Write-Host "*.githubusercontent.com must be reachable; set the proxy in Windows Settings > Network & internet > Proxy."
                exit 1
            }
            $Actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $Zip).Hash.ToLower()
            if ($Actual -ne $Sha256) {
                Remove-Item -LiteralPath $Zip
                Write-Host "Checksum mismatch for idevice-tools: $Actual"
                Write-Host "Expected: $Sha256"
                Write-Host "A proxy may have changed the download. Nothing was run."
                exit 1
            }
            try {
                Expand-Archive -LiteralPath $Zip -DestinationPath $Dir -Force
            } catch {
                Write-Host "Could not unpack idevice-tools: $($_.Exception.Message)"
                Write-AntivirusHint
                exit 1
            }
        } finally {
            $ProgressPreference = $OldProgress
        }
        Remove-Item -LiteralPath $Zip
        if (-not ((Test-Path -LiteralPath $Bin) -and (Test-Path -LiteralPath $List))) {
            Write-Host "idevice-tools was unpacked, but its programs are gone."
            Write-AntivirusHint
            exit 1
        }
        Set-Content -LiteralPath $Marker -Value "$Version $Sha256"
    }

    # Native tools write to stderr; with "Stop" Windows PowerShell 5.1 would turn that into an exception.
    $ErrorActionPreference = "Continue"
    # idevice-tools is written in Rust; its RUST_LOG output on stderr would count as an error below.
    $env:RUST_LOG = $null

    $UdidArgs = @()
    if ($Udid) {
        $UdidArgs = @("--udid", $Udid)
    } else {
        $Devices = & $List 2>&1 | ForEach-Object { "$_" }
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Could not list the connected devices (idevice_id exit code $LASTEXITCODE):"
            if ($Devices) { $Devices | ForEach-Object { Write-Host "  $_" } }
            Write-Host ""
            Write-Checklist
            exit 1
        }
        $Usb = @()
        $IsUsb = $false
        foreach ($Line in $Devices) {
            if ($Line -match "connection_type:") { $IsUsb = $Line -match "connection_type: Usb," }
            if ($IsUsb -and $Line -match 'udid: "([^"]+)"') { $Usb += $Matches[1] }
        }
        $Usb = @($Usb | Sort-Object -Unique)
        if ($Usb.Count -gt 1) {
            Write-Host "More than one iPhone or iPad is connected over USB:"
            $Usb | ForEach-Object { Write-Host "  $_" }
            Write-Host "Connect only one, or pick one with:"
            Write-Host "  powershell -NoProfile -ExecutionPolicy Bypass -File make-pairing.ps1 -Udid <UDID>"
            exit 1
        }
        if ($Usb.Count -eq 0) {
            Write-Host "No iPhone or iPad is connected over USB."
            Write-Host ""
            Write-Checklist
            exit 1
        }
        # Explicit, so a device that usbmuxd only sees over the network is not picked instead.
        $UdidArgs = @("--udid", $Usb[0])
    }

    if ($PairDir) {
        New-Item -ItemType Directory -Force -Path $PairDir | Out-Null
        # Only the current user, by SID (works for domain and Entra ID accounts); new files inherit this.
        icacls "$PairDir" /inheritance:r /grant:r "*$($Sid):(OI)(CI)F" | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Could not restrict access to $PairDir."
            exit 1
        }
    }
    $Started = $true
    if (Test-Path -LiteralPath $Out) { Remove-Item -LiteralPath $Out -Force }

    Write-Host "Unlock the iPhone or iPad. If it asks, tap Trust and enter the passcode."
    $PairLog = & $Bin @UdidArgs remotepairing_lockdown pair $Hostname $Out 2>&1 | ForEach-Object { "$_" }
    $Written = (Test-Path -LiteralPath $Out) -and ((Get-Item -LiteralPath $Out).Length -gt 0)
    if ($LASTEXITCODE -ne 0 -or -not $Written) {
        Write-Host "Pairing failed:"
        if ($PairLog) { $PairLog | ForEach-Object { Write-Host $_ } } else { Write-Host "no output from idevice-tools" }
        Write-Host ""
        Write-Checklist
        exit 1
    }

    # Only the current user may read the file. Modify keeps it deletable.
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
        Write-Host "Is LocSim installed and the device unlocked?"
        Write-Host ""
        Write-Host "The pairing file is at: $Out"
        Write-Host "It contains a private key that grants access to this device."
        Write-Host "Move it to the device, for example with the Apple Devices app (Files tab > LocSim)."
        Write-Host "Avoid cloud storage and email. Delete it here afterwards."
        exit 3
    }
} finally {
    $env:RUST_LOG = $OldRustLog
    # A pairing file from a failed or interrupted run must not stay on the disk.
    if ($Started -and -not $Kept -and (Test-Path -LiteralPath $Out)) { Remove-Item -LiteralPath $Out -Force }
    if ($OldEncoding) {
        try { [Console]::OutputEncoding = $OldEncoding } catch { }
    }
}
