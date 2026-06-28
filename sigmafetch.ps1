# sigmafetch.ps1 - Fetch info tool for Windows
# Run: powershell -ExecutionPolicy Bypass -File sigmafetch.ps1

$SHOW_LOGO = $true   # Set to $false to hide Windows logo

# ─────────────────────────────────────────────
#  LOGO
# ─────────────────────────────────────────────
function Get-WindowsLogo {
    $lines = @(
        "                      ",
        "                      ",
        "                 ...::",
        "          ...:::::::::",
        " ....:::: ::::::::::::",
        " :::::::: ::::::::::::",
        " :::::::: ::::::::::::",
        " ........ ............",
        " :::::::: ::::::::::::",
        " :::::::: ::::::::::::",
        " '''':::: ::::::::::::",
        "          ''':::::::::",
        "                 '''::",
        "                      ",
        "                      "
    )
    return $lines
}

# ─────────────────────────────────────────────
#  PROGRESS BAR
# ─────────────────────────────────────────────
function Show-Progress {
    param([string]$Message, [int]$Step, [int]$Total)
    $pct    = [int](($Step / $Total) * 100)
    $filled = [int](($Step / $Total) * 30)
    $bar    = ("#" * $filled) + ("-" * (30 - $filled))
    Write-Host "`r  [$bar] $pct%  $Message                    " -NoNewline -ForegroundColor Cyan
}

# ─────────────────────────────────────────────
#  CPU NAME CLEANUP
# ─────────────────────────────────────────────
function Clean-CpuName {
    param([string]$Name)
    $n = $Name
    $n = $n -replace '\(R\)|\(TM\)',                    ''
    $n = $n -replace '\d+(st|nd|rd|th) Gen ',           ''
    $n = $n -replace ' CPU',                            ''
    $n = $n -replace ' @.+',                            ''
    $n = $n -replace ' \d+-Core Processor',             ''
    $n = $n -replace ' (Six|Eight|Quad|Dual|Hexa|Octa|Deca|Twelve|Sixteen|Thirty-Two|Sixty-Four)-Core Processor', ''
    $n = $n -replace ' with Radeon.*',                  ''
    $n = $n -replace ' APU with.*',                     ''
    $n = $n -replace ' Radeon R\d,.*',                  ''
    $n = $n -replace ' \d+-Cores?',                     ''
    $n = $n -replace 'Core\(TM\)2',                     'Core 2'
    $n = $n -replace 'Pentium Dual-Core',               'Pentium'
    $n = $n -replace '^Intel ',                         ''
    $n = $n -replace '^AMD ',                           ''
    $n = $n -replace '\s+',                             ' '
    $n = $n.Trim()
    return $n
}

# ─────────────────────────────────────────────
#  DATA COLLECTION
# ─────────────────────────────────────────────
$totalSteps = 13
$step       = 0

Write-Host ""
Write-Host "  Collecting system info..." -ForegroundColor DarkGray
Write-Host ""

# OS
$step++; Show-Progress "OS info..." $step $totalSteps
$osInfo    = Get-CimInstance Win32_OperatingSystem
$osName    = $osInfo.Caption -replace '^.+?(?=Windows)', ''
$osVersion = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue).DisplayVersion
if (-not $osVersion) { $osVersion = $osInfo.Version }
$osString  = "$osName $osVersion"

# Uptime
$step++; Show-Progress "Uptime..." $step $totalSteps
$uptimeSecs  = (Get-Date) - $osInfo.LastBootUpTime
$installDate = $osInfo.InstallDate
$installDays = [int]((Get-Date) - $installDate).TotalDays
if ($uptimeSecs.TotalMinutes -lt 60) {
    $uptimeStr = "$([int]$uptimeSecs.TotalMinutes)min"
} elseif ($uptimeSecs.TotalHours -lt 24) {
    $uptimeStr = "$([int]$uptimeSecs.TotalHours)h"
} else {
    $uptimeStr = "$([int]$uptimeSecs.TotalDays)days"
}
$uptimeString = "$uptimeStr ($($installDays)days)"

# Streak — longest continuous uptime + overall usage %
# Event ID 6005 = system start, 6006 = system shutdown (clean) / 41 = unexpected reboot
$step++; Show-Progress "Usage streak..." $step $totalSteps
$streakString = "Unknown"
try {
    $filterXml = @"
<QueryList>
  <Query Id="0" Path="System">
    <Select Path="System">*[System[(EventID=6005 or EventID=6006)]]</Select>
  </Query>
</QueryList>
"@
    $events = Get-WinEvent -FilterXml $filterXml -ErrorAction Stop |
              Sort-Object TimeCreated

    if ($events.Count -ge 2) {
        $longestStreak = [TimeSpan]::Zero
        $totalDowntime = [TimeSpan]::Zero
        $lastShutdown  = $null
        $lastBoot      = $null

        foreach ($evt in $events) {
            if ($evt.Id -eq 6005) {
                # Boot event
                if ($lastShutdown -ne $null) {
                    $gap = $evt.TimeCreated - $lastShutdown
                    if ($gap.TotalSeconds -gt 0) { $totalDowntime += $gap }
                }
                $lastBoot = $evt.TimeCreated
            } elseif ($evt.Id -eq 6006 -and $lastBoot -ne $null) {
                # Shutdown event — measure this session
                $session = $evt.TimeCreated - $lastBoot
                if ($session -gt $longestStreak) { $longestStreak = $session }
                $lastShutdown = $evt.TimeCreated
                $lastBoot     = $null
            }
        }

        # Current session is still running — compare it too
        if ($lastBoot -ne $null) {
            $currentSession = (Get-Date) - $lastBoot
            if ($currentSession -gt $longestStreak) { $longestStreak = $currentSession }
        }

        # Usage % = (total time since install - total downtime) / total time since install
        $totalSpan = (Get-Date) - $installDate
        if ($totalSpan.TotalSeconds -gt 0) {
            $usagePct = [int]([math]::Round(
                ($totalSpan.TotalSeconds - $totalDowntime.TotalSeconds) /
                $totalSpan.TotalSeconds * 100
            ))
            $usagePct = [math]::Max(0, [math]::Min(100, $usagePct))
        } else {
            $usagePct = 0
        }

        # Format longest streak duration
        if ($longestStreak.TotalMinutes -lt 60) {
            $streakLen = "$([int]$longestStreak.TotalMinutes)min"
        } elseif ($longestStreak.TotalHours -lt 24) {
            $streakLen = "$([int]$longestStreak.TotalHours)h"
        } else {
            $streakLen = "$([int]$longestStreak.TotalDays)days"
        }

        $streakString = "$streakLen ($usagePct%)"
    }
} catch {
    $streakString = "Unknown (no event log access)"
}

# Installed programs
$step++; Show-Progress "Programs..." $step $totalSteps
$regPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
)
$installedCount = ($regPaths | ForEach-Object {
    Get-ItemProperty $_ -ErrorAction SilentlyContinue
} | Where-Object { $_.DisplayName -and $_.SystemComponent -ne 1 } | Select-Object -Unique DisplayName).Count

# Processes
$step++; Show-Progress "Processes..." $step $totalSteps
$processCount = (Get-Process).Count

# CPU
$step++; Show-Progress "CPU..." $step $totalSteps
$cpuRaw     = (Get-CimInstance Win32_Processor | Select-Object -First 1)
$cpuName    = Clean-CpuName $cpuRaw.Name
$cpuCores   = $cpuRaw.NumberOfCores
$cpuFreqMHz = $cpuRaw.MaxClockSpeed
if ($cpuFreqMHz -ge 1000) {
    $cpuFreqStr = "$([math]::Round($cpuFreqMHz / 1000, 1))GHz"
} else {
    $cpuFreqStr = "${cpuFreqMHz}MHz"
}
$cpuString = "$cpuName ($cpuFreqStr / $cpuCores cores)"

# RAM
$step++; Show-Progress "RAM..." $step $totalSteps
$ramFreeKB  = $osInfo.FreePhysicalMemory
$ramTotalKB = $osInfo.TotalVisibleMemorySize

# Физическая ёмкость — сумма планок
$physicalRAMBytes = 0
try {
    $dimms = Get-CimInstance Win32_PhysicalMemory
    foreach ($d in $dimms) { $physicalRAMBytes += $d.Capacity }
} catch {}

if ($physicalRAMBytes -gt 0) {
    $ramGB = [math]::Round($physicalRAMBytes / 1GB, 0)
} else {
    # фолбек — округляем TotalVisibleMemorySize до ближайшей степени двойки
    $ramGB = [math]::Pow(2, [math]::Ceiling([math]::Log($ramTotalKB / 1MB, 2)))
    $ramGB = [int]$ramGB
}

$ramUsedPct = [int](($ramTotalKB - $ramFreeKB) / $ramTotalKB * 100)

$memType = 0
try { $memType = (Get-CimInstance Win32_PhysicalMemory | Select-Object -First 1).SMBIOSMemoryType } catch {}
$ddrType = switch ($memType) {
    20 { "DDR" }; 21 { "DDR2" }; 24 { "DDR3" }; 26 { "DDR4" }; 34 { "DDR5" }; default { "DDR" }
}
$ramString = "${ramGB}GB $ddrType ($ramUsedPct%)"






# GPU
$step++; Show-Progress "GPU..." $step $totalSteps
$gpus       = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -notmatch 'Microsoft|Remote|Basic' }
$gpuStrings = @()
foreach ($gpu in $gpus) {
    $gpuName   = $gpu.Name
    $vramBytes = 0
    try {
        $regKeys  = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}" -ErrorAction SilentlyContinue
        $matchKey = $null
        foreach ($k in $regKeys) {
            $d = Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue
            if ($d.DriverDesc -and $d.DriverDesc.Trim() -eq $gpuName.Trim()) { $matchKey = $d; break }
        }
        if (-not $matchKey) {
            foreach ($k in $regKeys) {
                $d = Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue
                if ($d.DriverDesc -and $gpuName -like "*$($d.DriverDesc.Trim())*") { $matchKey = $d; break }
            }
        }
        if ($matchKey) {
            $raw = $matchKey.'HardwareInformation.qwMemorySize'
            if ($raw -is [byte[]]) { $vramBytes = [System.BitConverter]::ToInt64($raw, 0) }
            elseif ($raw)          { $vramBytes = [int64]$raw }
        }
    } catch {}
    if (-not $vramBytes -or $vramBytes -le 0) { $vramBytes = $gpu.AdapterRAM }
    $vramGB  = if ($vramBytes -gt 0) { [math]::Round($vramBytes / 1GB, 0) } else { 0 }
    $vramStr = if ($vramGB -gt 0) { " ${vramGB}GB" } else { "" }
    $gpuStrings += "$gpuName$vramStr"
}

# Discs
$step++; Show-Progress "Discs..." $step $totalSteps
$diskStrings = @()
try {
    $physDisks = Get-PhysicalDisk | Sort-Object DeviceId
    foreach ($pd in $physDisks) {
        $sizeGB  = [math]::Round($pd.Size / 1GB, 0)
        $sizeStr = if ($sizeGB -ge 1000) { "$([math]::Round($sizeGB / 1000, 0))TB" } else { "${sizeGB}GB" }
        $dtype   = if ($pd.MediaType -eq 'SSD') { 'SSD' } elseif ($pd.MediaType -eq 'HDD') { 'HDD' } else { $pd.MediaType }
        $diskStrings += "$sizeStr $dtype $($pd.FriendlyName)"
    }
} catch {
    foreach ($d in (Get-CimInstance Win32_DiskDrive | Sort-Object Index)) {
        $sizeGB  = [math]::Round($d.Size / 1GB, 0)
        $sizeStr = if ($sizeGB -ge 1000) { "$([math]::Round($sizeGB / 1000, 0))TB" } else { "${sizeGB}GB" }
        $diskStrings += "$sizeStr $($d.Model)"
    }
}

# Displays
$step++; Show-Progress "Displays..." $step $totalSteps
$displayStrings = @()
try {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Display {
    [DllImport("user32.dll")] public static extern bool EnumDisplaySettings(string device, int mode, ref DEVMODE dm);
    [StructLayout(LayoutKind.Sequential)] public struct DEVMODE {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string dmDeviceName;
        public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra;
        public int dmFields;
        public int dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput;
        public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string dmFormName;
        public short dmLogPixels;
        public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
    }
}
"@ -ErrorAction SilentlyContinue
    $monitors = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction SilentlyContinue
    $idx = 1
    foreach ($mon in $monitors) {
        $dm = New-Object Display+DEVMODE
        if ([Display]::EnumDisplaySettings("\\.\DISPLAY$idx", -1, [ref]$dm)) {
            $displayStrings += "$($dm.dmPelsWidth)x$($dm.dmPelsHeight) @$($dm.dmDisplayFrequency)Hz"
        }
        $idx++
    }
    if ($displayStrings.Count -eq 0) { throw "fallback" }
} catch {
    foreach ($s in (Get-CimInstance Win32_VideoController)) {
        if ($s.CurrentHorizontalResolution -and $s.CurrentVerticalResolution) {
            $displayStrings += "$($s.CurrentHorizontalResolution)x$($s.CurrentVerticalResolution) @$($s.CurrentRefreshRate)Hz"
        }
    }
}


# Done
$step++; Show-Progress "Done" $totalSteps $totalSteps
Start-Sleep -Milliseconds 200
Clear-Host

# ─────────────────────────────────────────────
#  OUTPUT
# ─────────────────────────────────────────────
$cyan   = "Cyan"
$white  = "White"
$gray   = "DarkGray"
$yellow = "Yellow"

$infoLines = @(
    @{ label = "[Software]"; value = $null;                      color = $yellow }
    @{ label = "OS";         value = $osString;                  color = $white  }
    @{ label = "Uptime";     value = $uptimeString;              color = $white  }
    @{ label = "Streak";     value = $streakString;              color = $white  }
    @{ label = "Install";    value = "$installedCount programs"; color = $white  }
    @{ label = "Runs";       value = "$processCount processes";  color = $white  }
    @{ label = "[Hardware]"; value = $null;                      color = $yellow }
    @{ label = "CPU";        value = $cpuString;                 color = $white  }
    @{ label = "MEM";        value = $ramString;                 color = $white  }
)
foreach ($g in $gpuStrings) {
    $infoLines += @{ label = "GPU"; value = $g; color = $white }
}
$di = 1
foreach ($d in $diskStrings)   { $infoLines += @{ label = "Disc $di";    value = $d; color = $white }; $di++ }
$di = 1
foreach ($d in $displayStrings) { $infoLines += @{ label = "Display $di"; value = $d; color = $white }; $di++ }

# Logo + info side by side
$logoLines = @()
if ($SHOW_LOGO) { $logoLines = Get-WindowsLogo }

$maxLines = [math]::Max($logoLines.Count, $infoLines.Count)

Write-Host ""
for ($i = 0; $i -lt $maxLines; $i++) {
    if ($i -lt $logoLines.Count) {
        Write-Host $logoLines[$i] -ForegroundColor Cyan -NoNewline
    } else {
        Write-Host (" " * 22) -NoNewline
    }

    if ($i -lt $infoLines.Count) {
        $item = $infoLines[$i]
        if ($null -eq $item.value) {
            Write-Host "  $($item.label)" -ForegroundColor $item.color
        } else {
            Write-Host "  |- " -ForegroundColor $gray -NoNewline
            Write-Host "$($item.label): " -ForegroundColor $cyan -NoNewline
            Write-Host $item.value -ForegroundColor $item.color
        }
    } else {
        Write-Host ""
    }
}

Write-Host ""
Write-Host ("  " + ("-" * 58)) -ForegroundColor $gray
Write-Host ""
