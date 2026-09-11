[CmdletBinding()]
param(
    [ValidateSet('Apply', 'Set1440', 'Set1920', 'SetNative', 'Disable', 'Enable', 'Restore', 'DryRun', 'DryRun1440', 'DryRun1920', 'Status')]
    [string]$Action = 'Apply',
    [switch]$AllowSoleDisplayDisable,
    [string]$TargetInstanceId,
    [switch]$NonInteractive
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$StateRoot = Join-Path $env:ProgramData 'MonitorModeConsole'
$StatePath = Join-Path $StateRoot 'state.json'
$TargetWidth = if ($Action -in @('Set1440', 'DryRun1440')) { 1440 } elseif ($Action -in @('Set1920', 'DryRun1920')) { 1920 } else { 1280 }
$TargetHeight = if ($Action -in @('Set1920', 'DryRun1920')) { 1440 } elseif ($Action -in @('Set1440', 'DryRun1440')) { 1080 } else { 880 }

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if ($Action -notin @('DryRun', 'DryRun1440', 'DryRun1920', 'Status') -and -not (Test-Administrator)) {
    throw 'Run this script from an elevated PowerShell window (Run as administrator).'
}

$legacyStatePath = Join-Path $PSScriptRoot 'Monitor-1280x880.state.json'

if (-not (Get-Module -ListAvailable -Name PnpDevice)) {
    throw 'The Windows PnpDevice PowerShell module is not available on this system.'
}
Import-Module PnpDevice

if (-not ('MonitorMode.NativeDisplay' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace MonitorMode {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DISPLAY_DEVICE {
        public int cb;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string DeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceString;
        public int StateFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceID;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceKey;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DEVMODE {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
        public short dmSpecVersion;
        public short dmDriverVersion;
        public short dmSize;
        public short dmDriverExtra;
        public int dmFields;
        public int dmPositionX;
        public int dmPositionY;
        public int dmDisplayOrientation;
        public int dmDisplayFixedOutput;
        public short dmColor;
        public short dmDuplex;
        public short dmYResolution;
        public short dmTTOption;
        public short dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
        public short dmLogPixels;
        public int dmBitsPerPel;
        public int dmPelsWidth;
        public int dmPelsHeight;
        public int dmDisplayFlags;
        public int dmDisplayFrequency;
        public int dmICMMethod;
        public int dmICMIntent;
        public int dmMediaType;
        public int dmDitherType;
        public int dmReserved1;
        public int dmReserved2;
        public int dmPanningWidth;
        public int dmPanningHeight;
    }

    public class DevModeInfo {
        public int Fields { get; set; }
        public int PositionX { get; set; }
        public int PositionY { get; set; }
        public int DisplayOrientation { get; set; }
        public int DisplayFixedOutput { get; set; }
        public int BitsPerPel { get; set; }
        public int PelsWidth { get; set; }
        public int PelsHeight { get; set; }
        public int DisplayFlags { get; set; }
        public int DisplayFrequency { get; set; }
    }

    public class DisplayInfo {
        public string DeviceName { get; set; }
        public string AdapterName { get; set; }
        public string MonitorName { get; set; }
        public string MonitorInterfacePath { get; set; }
        public int CurrentWidth { get; set; }
        public int CurrentHeight { get; set; }
        public int CurrentFrequency { get; set; }
        public DevModeInfo CurrentMode { get; set; }
        public bool IsPrimary { get; set; }
    }

    public class ModeInfo {
        public int Width { get; set; }
        public int Height { get; set; }
        public int Frequency { get; set; }
    }

    public static class NativeDisplay {
        const int ENUM_CURRENT_SETTINGS = -1;
        const int ENUM_REGISTRY_SETTINGS = -2;
        const int DISPLAY_DEVICE_ACTIVE = 0x1;
        const int DISPLAY_DEVICE_PRIMARY_DEVICE = 0x4;
        const int EDD_GET_DEVICE_INTERFACE_NAME = 0x1;
        const int DM_BITSPERPEL = 0x00040000;
        const int DM_PELSWIDTH = 0x00080000;
        const int DM_PELSHEIGHT = 0x00100000;
        const int DM_DISPLAYFREQUENCY = 0x00400000;
        const int CDS_UPDATEREGISTRY = 0x1;
        const int CDS_TEST = 0x2;
        const int CDS_NORESET = 0x10000000;

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        static extern bool EnumDisplayDevices(string device, uint index, ref DISPLAY_DEVICE displayDevice, uint flags);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        static extern bool EnumDisplaySettings(string deviceName, int modeNum, ref DEVMODE devMode);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        static extern int ChangeDisplaySettingsEx(string deviceName, ref DEVMODE devMode, IntPtr hwnd, int flags, IntPtr lParam);

        static DISPLAY_DEVICE NewDisplayDevice() {
            DISPLAY_DEVICE device = new DISPLAY_DEVICE();
            device.cb = Marshal.SizeOf(typeof(DISPLAY_DEVICE));
            return device;
        }

        static DEVMODE NewDevMode() {
            DEVMODE mode = new DEVMODE();
            mode.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
            return mode;
        }

        static DevModeInfo ToModeInfo(DEVMODE mode) {
            return new DevModeInfo {
                Fields = mode.dmFields,
                PositionX = mode.dmPositionX,
                PositionY = mode.dmPositionY,
                DisplayOrientation = mode.dmDisplayOrientation,
                DisplayFixedOutput = mode.dmDisplayFixedOutput,
                BitsPerPel = mode.dmBitsPerPel,
                PelsWidth = mode.dmPelsWidth,
                PelsHeight = mode.dmPelsHeight,
                DisplayFlags = mode.dmDisplayFlags,
                DisplayFrequency = mode.dmDisplayFrequency
            };
        }

        public static DisplayInfo[] GetActiveDisplays() {
            var results = new System.Collections.Generic.List<DisplayInfo>();
            uint adapterIndex = 0;
            DISPLAY_DEVICE adapter = NewDisplayDevice();
            while (EnumDisplayDevices(null, adapterIndex, ref adapter, 0)) {
                if ((adapter.StateFlags & DISPLAY_DEVICE_ACTIVE) != 0) {
                    DEVMODE current = NewDevMode();
                    if (EnumDisplaySettings(adapter.DeviceName, ENUM_CURRENT_SETTINGS, ref current)) {
                        DISPLAY_DEVICE monitor = NewDisplayDevice();
                        string monitorName = "Unknown monitor";
                        string interfacePath = "";
                        if (EnumDisplayDevices(adapter.DeviceName, 0, ref monitor, EDD_GET_DEVICE_INTERFACE_NAME)) {
                            monitorName = monitor.DeviceString;
                            interfacePath = monitor.DeviceID;
                        }
                        results.Add(new DisplayInfo {
                            DeviceName = adapter.DeviceName,
                            AdapterName = adapter.DeviceString,
                            MonitorName = monitorName,
                            MonitorInterfacePath = interfacePath,
                            CurrentWidth = current.dmPelsWidth,
                            CurrentHeight = current.dmPelsHeight,
                            CurrentFrequency = current.dmDisplayFrequency,
                            CurrentMode = ToModeInfo(current),
                            IsPrimary = (adapter.StateFlags & DISPLAY_DEVICE_PRIMARY_DEVICE) != 0
                        });
                    }
                }
                adapterIndex++;
                adapter = NewDisplayDevice();
            }
            return results.ToArray();
        }

        public static ModeInfo[] GetModes(string deviceName, int width, int height) {
            var modes = new System.Collections.Generic.List<ModeInfo>();
            int modeIndex = 0;
            DEVMODE mode = NewDevMode();
            while (EnumDisplaySettings(deviceName, modeIndex, ref mode)) {
                if (mode.dmPelsWidth == width && mode.dmPelsHeight == height) {
                    bool duplicate = false;
                    foreach (ModeInfo item in modes) {
                        if (item.Frequency == mode.dmDisplayFrequency) { duplicate = true; break; }
                    }
                    if (!duplicate) {
                        modes.Add(new ModeInfo { Width = width, Height = height, Frequency = mode.dmDisplayFrequency });
                    }
                }
                modeIndex++;
                mode = NewDevMode();
            }
            return modes.ToArray();
        }

        public static DevModeInfo GetRegistryMode(string deviceName) {
            DEVMODE mode = NewDevMode();
            return EnumDisplaySettings(deviceName, ENUM_REGISTRY_SETTINGS, ref mode) ? ToModeInfo(mode) : null;
        }

        public static int PersistModeNoReset(string deviceName, int width, int height, int frequency, int bitsPerPel) {
            DEVMODE mode = NewDevMode();
            mode.dmPelsWidth = width;
            mode.dmPelsHeight = height;
            mode.dmDisplayFrequency = frequency;
            mode.dmBitsPerPel = bitsPerPel > 0 ? bitsPerPel : 32;
            mode.dmFields = DM_PELSWIDTH | DM_PELSHEIGHT | DM_DISPLAYFREQUENCY | DM_BITSPERPEL;
            return ChangeDisplaySettingsEx(deviceName, ref mode, IntPtr.Zero,
                CDS_UPDATEREGISTRY | CDS_NORESET, IntPtr.Zero);
        }

        public static int SetMode(string deviceName, int width, int height, int frequency, bool testOnly) {
            DEVMODE mode = NewDevMode();
            mode.dmPelsWidth = width;
            mode.dmPelsHeight = height;
            mode.dmDisplayFrequency = frequency;
            mode.dmBitsPerPel = 32;
            mode.dmFields = DM_PELSWIDTH | DM_PELSHEIGHT | DM_DISPLAYFREQUENCY | DM_BITSPERPEL;
            return ChangeDisplaySettingsEx(deviceName, ref mode, IntPtr.Zero,
                testOnly ? CDS_TEST : CDS_UPDATEREGISTRY, IntPtr.Zero);
        }
    }
}
'@
}

function Convert-InterfacePathToInstanceId {
    param([AllowEmptyString()][string]$InterfacePath)

    if ([string]::IsNullOrWhiteSpace($InterfacePath) -or $InterfacePath -notmatch '^\\\\\?\\DISPLAY#([^#]+)#([^#]+)#') {
        return $null
    }
    return ('DISPLAY\{0}\{1}' -f $Matches[1], $Matches[2])
}

function Get-ActiveMonitorChoices {
    $choices = @()
    foreach ($display in [MonitorMode.NativeDisplay]::GetActiveDisplays()) {
        $instanceId = Convert-InterfacePathToInstanceId -InterfacePath $display.MonitorInterfacePath
        if (-not $instanceId) { continue }

        $device = Get-PnpDevice -InstanceId $instanceId -Class Monitor -PresentOnly -ErrorAction SilentlyContinue
        if ($null -eq $device) { continue }
        $choices += [pscustomobject]@{
            DeviceName = $display.DeviceName
            MonitorInterfacePath = $display.MonitorInterfacePath
            CurrentMode = $display.CurrentMode
            AdapterName = $display.AdapterName
            MonitorName = $display.MonitorName
            InstanceId = $device.InstanceId
            CurrentWidth = $display.CurrentWidth
            CurrentHeight = $display.CurrentHeight
            CurrentFrequency = $display.CurrentFrequency
            IsPrimary = $display.IsPrimary
        }
    }
    return @($choices)
}

function Select-FromList {
    param(
        [Parameter(Mandatory)][array]$Items,
        [Parameter(Mandatory)][string]$Prompt
    )

    if ($Items.Count -eq 0) { throw 'No matching monitor was found.' }
    for ($i = 0; $i -lt $Items.Count; $i++) {
        $item = $Items[$i]
        Write-Host ('[{0}] {1} | {2} | {3}x{4} @{5}Hz | {6}' -f `
            ($i + 1), $item.DeviceName, $item.MonitorName, $item.CurrentWidth, `
            $item.CurrentHeight, $item.CurrentFrequency, $item.AdapterName)
    }
    do {
        $raw = Read-Host $Prompt
        $number = 0
        $valid = [int]::TryParse($raw, [ref]$number) -and $number -ge 1 -and $number -le $Items.Count
        if (-not $valid) { Write-Warning 'Enter one of the displayed numbers.' }
    } until ($valid)
    return $Items[$number - 1]
}

function Test-ModeMatches {
    param($Display, [int]$Width, [int]$Height, [int]$Frequency)
    return $null -ne $Display -and $Display.CurrentWidth -eq $Width -and `
        $Display.CurrentHeight -eq $Height -and $Display.CurrentFrequency -eq $Frequency
}

function Write-RecoveryState {
    param([Parameter(Mandatory)]$State)
    $temporaryPath = '{0}.{1}.{2}.tmp' -f $StatePath, $PID, ([Guid]::NewGuid().ToString('N'))
    try {
        $State | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temporaryPath -Encoding UTF8
        Move-Item -LiteralPath $temporaryPath -Destination $StatePath -Force
    } finally {
        if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue }
    }
}

function Read-RecoveryState {
    param([switch]$ReadOnly)
    if (-not (Test-Path -LiteralPath $StatePath)) { return $null }
    $state = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
    if ([int]$state.Version -lt 3) {
        $device = Get-PnpDevice -InstanceId $state.InstanceId -ErrorAction SilentlyContinue
        if ([int]$state.Version -ge 2) {
            $baseline = $state.Baseline
            $lastMode = $state.LastAppliedMode
        } else {
            $baseline = [pscustomobject]@{ Width = [int]$state.OriginalWidth; Height = [int]$state.OriginalHeight; Frequency = [int]$state.OriginalFrequency }
            $lastMode = [pscustomobject]@{ Width = [int]$state.AppliedWidth; Height = [int]$state.AppliedHeight; Frequency = [int]$state.AppliedFrequency }
        }
        $state = [pscustomobject]@{
            Version = 3; SavedAt = $state.SavedAt; InstanceId = $state.InstanceId
            MonitorName = $state.MonitorName; AdapterName = $state.AdapterName
            OperationKind = 'Migrated'; Phase = 'Migrated'
            MonitorDisabledByTool = ($null -eq $device -or $device.Status -ne 'OK')
            Baseline = $baseline; LastAppliedMode = $lastMode
            Supports1280 = $true; Supports1440 = $true; Allows1920 = $false
            LastRestoreAttempt = $null; LastError = $null
        }
    }
    if ([int]$state.Version -lt 5) {
        $lastKnownMode = if ($state.PSObject.Properties['LastKnownMode'] -and $state.LastKnownMode) { $state.LastKnownMode } elseif ($state.LastAppliedMode) { $state.LastAppliedMode } else { $state.Baseline }
        $activeDisplayCount = if ($state.PSObject.Properties['ActiveDisplayCountBeforeDisable']) { [int]$state.ActiveDisplayCountBeforeDisable } else { 0 }
        $wasSoleDisplay = if ($state.PSObject.Properties['WasSoleDisplayAtDisable']) { [bool]$state.WasSoleDisplayAtDisable } else { $false }
        $state = [pscustomobject]@{
            Version = 5; SavedAt = $state.SavedAt; InstanceId = $state.InstanceId
            MonitorName = $state.MonitorName; AdapterName = $state.AdapterName
            OperationKind = $state.OperationKind; Phase = $state.Phase
            MonitorDisabledByTool = [bool]$state.MonitorDisabledByTool
            Baseline = $state.Baseline; LastAppliedMode = $state.LastAppliedMode; LastKnownMode = $lastKnownMode
            Supports1280 = [bool]$state.Supports1280; Supports1440 = [bool]$state.Supports1440; Allows1920 = [bool]$state.Allows1920
            ActiveDisplayCountBeforeDisable = $activeDisplayCount; WasSoleDisplayAtDisable = $wasSoleDisplay
            LastRestoreAttempt = $state.LastRestoreAttempt; LastError = $state.LastError
        }
        if (-not $ReadOnly) { Write-RecoveryState $state }
    }
    if ([int]$state.Version -lt 6) {
        $legacyDeviceName = if ($state.PSObject.Properties['DeviceNameBeforeDisable']) { [string]$state.DeviceNameBeforeDisable } else { $null }
        $state | Add-Member NoteProperty Version 6 -Force
        $state | Add-Member NoteProperty DeviceNameBeforeDisable $legacyDeviceName -Force
        $state | Add-Member NoteProperty MonitorInterfacePathBeforeDisable $null -Force
        $state | Add-Member NoteProperty DevModeBeforeDisable $null -Force
        $state | Add-Member NoteProperty DisableSnapshotCapturedAt $null -Force
        $state | Add-Member NoteProperty DisableSnapshotSource $null -Force
        $state | Add-Member NoteProperty LastRegistryMode $null -Force
        $state | Add-Member NoteProperty LastModeWrite $null -Force
        if (-not $ReadOnly) { Write-RecoveryState $state }
    }
    return $state
}

function Ensure-RecoveryBaseline {
    param([Parameter(Mandatory)]$Display)
    $state = Read-RecoveryState
    if ($state) {
        if ($state.InstanceId -ne $Display.InstanceId) { throw 'A recovery state already belongs to another monitor.' }
        Write-RecoveryState $state
        return $state
    }
    $native = Get-NativePanelSize -InstanceId $Display.InstanceId
    $state = [pscustomobject]@{
        Version = 6; SavedAt = (Get-Date).ToString('o'); InstanceId = $Display.InstanceId
        MonitorName = $Display.MonitorName; AdapterName = $Display.AdapterName
        OperationKind = 'Baseline'; Phase = 'BaselineSaved'; MonitorDisabledByTool = $false
        Baseline = [pscustomobject]@{ Width = [int]$Display.CurrentWidth; Height = [int]$Display.CurrentHeight; Frequency = [int]$Display.CurrentFrequency }
        LastAppliedMode = $null
        LastKnownMode = [pscustomobject]@{ Width = [int]$Display.CurrentWidth; Height = [int]$Display.CurrentHeight; Frequency = [int]$Display.CurrentFrequency }
        DeviceNameBeforeDisable = $null; MonitorInterfacePathBeforeDisable = $null; DevModeBeforeDisable = $null
        DisableSnapshotCapturedAt = $null; DisableSnapshotSource = $null
        LastRegistryMode = $null; LastModeWrite = $null
        Supports1280 = (Get-ModeCapability $Display 1280 880)
        Supports1440 = (Get-ModeCapability $Display 1440 1080)
        Allows1920 = ($native -and $native.Width -ge 1920 -and $native.Height -ge 1440 -and (Get-ModeCapability $Display 1920 1440))
        ActiveDisplayCountBeforeDisable = 0; WasSoleDisplayAtDisable = $false
        LastRestoreAttempt = $null; LastError = $null
    }
    Write-RecoveryState $state
    return $state
}

function New-DevModeSnapshot {
    param([Parameter(Mandatory)]$Mode)
    return [pscustomobject]@{
        Fields = [int]$Mode.Fields; PositionX = [int]$Mode.PositionX; PositionY = [int]$Mode.PositionY
        DisplayOrientation = [int]$Mode.DisplayOrientation; DisplayFixedOutput = [int]$Mode.DisplayFixedOutput
        BitsPerPel = [int]$Mode.BitsPerPel; PelsWidth = [int]$Mode.PelsWidth; PelsHeight = [int]$Mode.PelsHeight
        DisplayFlags = [int]$Mode.DisplayFlags; DisplayFrequency = [int]$Mode.DisplayFrequency
    }
}

function Test-OfflineModeSnapshot {
    param([Parameter(Mandatory)]$State)
    if (-not $State.PSObject.Properties['DeviceNameBeforeDisable'] -or [string]::IsNullOrWhiteSpace([string]$State.DeviceNameBeforeDisable)) { return $false }
    if (-not $State.PSObject.Properties['MonitorInterfacePathBeforeDisable'] -or [string]::IsNullOrWhiteSpace([string]$State.MonitorInterfacePathBeforeDisable)) { return $false }
    if ((Convert-InterfacePathToInstanceId $State.MonitorInterfacePathBeforeDisable) -ne $State.InstanceId) { return $false }
    if (-not $State.PSObject.Properties['DevModeBeforeDisable'] -or -not $State.DevModeBeforeDisable) { return $false }
    return [int]$State.DevModeBeforeDisable.BitsPerPel -gt 0 -and [int]$State.DevModeBeforeDisable.DisplayFrequency -gt 0
}

function Save-DisableSnapshot {
    param([Parameter(Mandatory)]$State, [Parameter(Mandatory)]$Display, [string]$Source = 'BeforeDisable')
    if ($Display.InstanceId -ne $State.InstanceId) { throw 'The display path does not belong to the saved monitor.' }
    if ([string]::IsNullOrWhiteSpace([string]$Display.DeviceName) -or [string]::IsNullOrWhiteSpace([string]$Display.MonitorInterfacePath) -or -not $Display.CurrentMode) {
        throw 'The display route and current mode could not be captured before disabling the monitor.'
    }
    Set-StateProperty $State DeviceNameBeforeDisable ([string]$Display.DeviceName)
    Set-StateProperty $State MonitorInterfacePathBeforeDisable ([string]$Display.MonitorInterfacePath)
    Set-StateProperty $State DevModeBeforeDisable (New-DevModeSnapshot $Display.CurrentMode)
    Set-StateProperty $State DisableSnapshotCapturedAt (Get-Date).ToString('o')
    Set-StateProperty $State DisableSnapshotSource $Source
}

function Get-NativePanelSize {
    param([Parameter(Mandatory)][string]$InstanceId)
    try {
        $registryPath = "Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\$InstanceId\Device Parameters"
        $edid = (Get-ItemProperty -LiteralPath $registryPath -Name EDID -ErrorAction Stop).EDID
        if ($null -eq $edid -or $edid.Length -lt 72) { return $null }
        $width = [int]$edid[56] + (([int]$edid[58] -band 0xF0) -shl 4)
        $height = [int]$edid[59] + (([int]$edid[61] -band 0xF0) -shl 4)
        if ($width -le 0 -or $height -le 0) { return $null }
        return [pscustomobject]@{ Width = $width; Height = $height }
    } catch { return $null }
}

function Get-ModeCapability {
    param([Parameter(Mandatory)]$Display, [int]$Width, [int]$Height)
    return $null -ne ([MonitorMode.NativeDisplay]::GetModes($Display.DeviceName, $Width, $Height) |
        Where-Object { $_.Frequency -eq $Display.CurrentFrequency } | Select-Object -First 1)
}

function Set-StateProperty {
    param([Parameter(Mandatory)]$State, [Parameter(Mandatory)][string]$Name, [AllowNull()]$Value)
    $State | Add-Member NoteProperty $Name $Value -Force
}

function Wait-ActiveSavedMonitor {
    param([Parameter(Mandatory)]$State, [int]$Attempts = 20)
    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        $candidate = @(Get-ActiveMonitorChoices) |
            Where-Object { $_.InstanceId -eq $State.InstanceId } |
            Select-Object -First 1
        if ($candidate) { return $candidate }
        Start-Sleep -Milliseconds 500
    }
    return $null
}

function Set-VerifiedDisplayMode {
    param(
        [Parameter(Mandatory)]$Display,
        [Parameter(Mandatory)][int]$Width,
        [Parameter(Mandatory)][int]$Height,
        [Parameter(Mandatory)][int]$Frequency
    )
    $testResult = [MonitorMode.NativeDisplay]::SetMode(
        $Display.DeviceName, $Width, $Height, $Frequency, $true
    )
    if ($testResult -ne 0) { throw "Windows rejected ${Width}x${Height} during testing (code $testResult)." }
    $applyResult = [MonitorMode.NativeDisplay]::SetMode(
        $Display.DeviceName, $Width, $Height, $Frequency, $false
    )
    if ($applyResult -ne 0) { throw "Windows could not apply ${Width}x${Height} (code $applyResult)." }
    Start-Sleep -Seconds 2
    $verified = [MonitorMode.NativeDisplay]::GetActiveDisplays() |
        Where-Object { (Convert-InterfacePathToInstanceId $_.MonitorInterfacePath) -eq $Display.InstanceId } |
        Select-Object -First 1
    if (-not (Test-ModeMatches $verified $Width $Height $Frequency)) {
        throw "${Width}x${Height} was requested but could not be verified."
    }
}

function Restore-OriginalMode {
    param([Parameter(Mandatory)]$State)

    $baseline = $State.Baseline
    for ($attempt = 1; $attempt -le 12; $attempt++) {
        $candidate = [MonitorMode.NativeDisplay]::GetActiveDisplays() |
            Where-Object { (Convert-InterfacePathToInstanceId $_.MonitorInterfacePath) -eq $State.InstanceId } |
            Select-Object -First 1
        if ($candidate) {
            if (Test-ModeMatches $candidate ([int]$baseline.Width) ([int]$baseline.Height) ([int]$baseline.Frequency)) { return $true }
            $testResult = [MonitorMode.NativeDisplay]::SetMode(
                $candidate.DeviceName, [int]$baseline.Width, [int]$baseline.Height,
                [int]$baseline.Frequency, $true
            )
            if ($testResult -eq 0) {
                $applyResult = [MonitorMode.NativeDisplay]::SetMode(
                    $candidate.DeviceName, [int]$baseline.Width, [int]$baseline.Height,
                    [int]$baseline.Frequency, $false
                )
                if ($applyResult -eq 0) {
                    Start-Sleep -Milliseconds 800
                    $verified = [MonitorMode.NativeDisplay]::GetActiveDisplays() |
                        Where-Object { (Convert-InterfacePathToInstanceId $_.MonitorInterfacePath) -eq $State.InstanceId } |
                        Select-Object -First 1
                    if (Test-ModeMatches $verified ([int]$baseline.Width) ([int]$baseline.Height) ([int]$baseline.Frequency)) { return $true }
                }
            }
        }
        Start-Sleep -Seconds 1
    }
    return $false
}

function Get-MonitorDeviceState {
    param([Parameter(Mandatory)][string]$InstanceId)
    $device = Get-PnpDevice -InstanceId $InstanceId -Class Monitor -PresentOnly -ErrorAction SilentlyContinue
    $problemCode = $null
    $problemCodeKnown = $false
    if ($device) {
        try {
            $problemCode = [int](Get-PnpDeviceProperty -InstanceId $InstanceId -KeyName 'DEVPKEY_Device_ProblemCode' -ErrorAction Stop).Data
            $problemCodeKnown = $true
        } catch { }
    }
    return [pscustomobject]@{
        Device = $device
        Missing = $null -eq $device
        Status = if ($device) { [string]$device.Status } else { 'Missing' }
        ProblemCode = $problemCode
        ProblemCodeKnown = $problemCodeKnown
        Disabled = $null -ne $device -and $problemCodeKnown -and $problemCode -eq 22
    }
}

function Assert-MonitorRemainsCode22 {
    param([Parameter(Mandatory)][string]$InstanceId)
    $deviceState = Get-MonitorDeviceState -InstanceId $InstanceId
    if ($deviceState.Missing) { throw 'The monitor disappeared while its disabled mode was being written.' }
    if (-not $deviceState.Disabled) { throw ('The monitor did not remain disabled (Problem Code: {0}).' -f $deviceState.ProblemCode) }
    return $deviceState
}

function Enable-ConfirmedMonitorDevice {
    param([Parameter(Mandatory)][string]$InstanceId)
    $deviceState = Get-MonitorDeviceState -InstanceId $InstanceId
    if ($deviceState.Missing) { throw 'The saved monitor is missing and cannot be enabled.' }
    if ($deviceState.Status -ne 'OK' -or $deviceState.ProblemCode -eq 22) {
        Write-Host "Enabling monitor: $InstanceId"
        Enable-PnpDevice -InstanceId $InstanceId -Confirm:$false
        for ($attempt = 1; $attempt -le 12; $attempt++) {
            Start-Sleep -Milliseconds 500
            $deviceState = Get-MonitorDeviceState -InstanceId $InstanceId
            if (-not $deviceState.Missing -and $deviceState.Status -eq 'OK' -and $deviceState.ProblemCode -ne 22) { return }
        }
        throw 'Windows did not report the monitor as enabled.'
    }
}

function Disable-ConfirmedMonitorDevice {
    param([Parameter(Mandatory)][string]$InstanceId)
    Disable-PnpDevice -InstanceId $InstanceId -Confirm:$false
    for ($attempt = 1; $attempt -le 10; $attempt++) {
        Start-Sleep -Milliseconds 500
        $deviceState = Get-MonitorDeviceState -InstanceId $InstanceId
        if ($deviceState.Missing) { throw 'The monitor disappeared before Windows confirmed that it was disabled.' }
        if ($deviceState.Disabled) { return }
    }
    throw 'Windows did not report the monitor as disabled.'
}

function Enable-MonitorOnly {
    param([Parameter(Mandatory)]$State)
    Set-StateProperty $State OperationKind 'DeviceEnable'
    Set-StateProperty $State Phase 'EnablePending'
    Write-RecoveryState $State
    try {
        Enable-ConfirmedMonitorDevice -InstanceId $State.InstanceId
        Set-StateProperty $State MonitorDisabledByTool $false
        Set-StateProperty $State Phase 'Enabled'
        Set-StateProperty $State LastError $null
        Write-RecoveryState $State
    } catch {
        Set-StateProperty $State Phase 'EnableFailed'
        Set-StateProperty $State LastError $_.Exception.Message
        Write-RecoveryState $State
        throw
    }
}

function Set-ModeWhileCode22 {
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)][string]$RequestedAction,
        [AllowNull()]$ResidualDisplay
    )
    [void](Assert-MonitorRemainsCode22 -InstanceId $State.InstanceId)
    if ($RequestedAction -eq 'SetNative') {
        $width = [int]$State.Baseline.Width
        $height = [int]$State.Baseline.Height
        $frequency = [int]$State.Baseline.Frequency
    } else {
        $width = if ($RequestedAction -eq 'Set1440') { 1440 } elseif ($RequestedAction -eq 'Set1920') { 1920 } else { 1280 }
        $height = if ($RequestedAction -eq 'Set1440') { 1080 } elseif ($RequestedAction -eq 'Set1920') { 1440 } else { 880 }
        $frequency = if ($ResidualDisplay) { [int]$ResidualDisplay.CurrentFrequency } elseif ($State.LastKnownMode) { [int]$State.LastKnownMode.Frequency } else { [int]$State.Baseline.Frequency }
    }
    if ($RequestedAction -eq 'Apply' -and -not [bool]$State.Supports1280) { throw '1280x880 was not supported before this monitor was disabled.' }
    if ($RequestedAction -eq 'Set1440' -and -not [bool]$State.Supports1440) { throw '1440x1080 was not supported before this monitor was disabled.' }
    if ($RequestedAction -eq 'Set1920' -and -not [bool]$State.Allows1920) { throw '1920x1440 is not allowed for this monitor.' }
    if ($RequestedAction -eq 'Set1920') {
        $native = Get-NativePanelSize -InstanceId $State.InstanceId
        if ($null -eq $native -or $native.Width -lt 1920 -or $native.Height -lt 1440) { throw '1920x1440 is blocked: this monitor is not a native 1440p-or-higher panel.' }
    }

    Set-StateProperty $State OperationKind 'ModeWriteWhileCode22'
    Set-StateProperty $State Phase 'Code22ModeWritePending'
    Set-StateProperty $State LastError $null
    Write-RecoveryState $State
    try {
        if ($ResidualDisplay) {
            if (-not (Test-OfflineModeSnapshot $State)) {
                Save-DisableSnapshot -State $State -Display $ResidualDisplay -Source 'ResidualPathWhileCode22'
                Write-RecoveryState $State
            }
            $available = [MonitorMode.NativeDisplay]::GetModes($ResidualDisplay.DeviceName, $width, $height) |
                Where-Object { $_.Frequency -eq $frequency } | Select-Object -First 1
            if (-not $available) { throw ('{0}x{1} at {2}Hz is not an existing driver mode.' -f $width, $height, $frequency) }
            [void](Assert-MonitorRemainsCode22 -InstanceId $State.InstanceId)
            Set-VerifiedDisplayMode $ResidualDisplay $width $height $frequency
            [void](Assert-MonitorRemainsCode22 -InstanceId $State.InstanceId)
            Set-StateProperty $State LastAppliedMode ([pscustomobject]@{ Width=$width; Height=$height; Frequency=$frequency })
            Set-StateProperty $State LastKnownMode $State.LastAppliedMode
            $disposition = 'AppliedNow'
            $verification = 'ActiveCurrentSettings'
        } else {
            if (-not (Test-OfflineModeSnapshot $State)) { throw 'The disabled monitor has no reliable v6 display-route snapshot. Explicitly enable it, then disable it once to capture the route.' }
            $conflict = [MonitorMode.NativeDisplay]::GetActiveDisplays() | Where-Object {
                $_.DeviceName -eq $State.DeviceNameBeforeDisable -and (Convert-InterfacePathToInstanceId $_.MonitorInterfacePath) -ne $State.InstanceId
            } | Select-Object -First 1
            if ($conflict) { throw 'The saved GDI display source now belongs to another active monitor; no offline write was attempted.' }
            [void](Assert-MonitorRemainsCode22 -InstanceId $State.InstanceId)
            $bitsPerPel = [int]$State.DevModeBeforeDisable.BitsPerPel
            $result = [MonitorMode.NativeDisplay]::PersistModeNoReset($State.DeviceNameBeforeDisable, $width, $height, $frequency, $bitsPerPel)
            if ($result -notin @(0, 1)) { throw "Windows rejected the disabled-mode registry write (code $result)." }
            [void](Assert-MonitorRemainsCode22 -InstanceId $State.InstanceId)
            $registryMode = [MonitorMode.NativeDisplay]::GetRegistryMode($State.DeviceNameBeforeDisable)
            if (-not $registryMode -or $registryMode.PelsWidth -ne $width -or $registryMode.PelsHeight -ne $height -or $registryMode.DisplayFrequency -ne $frequency) {
                throw 'Windows accepted the registry write but ENUM_REGISTRY_SETTINGS could not verify it.'
            }
            [void](Assert-MonitorRemainsCode22 -InstanceId $State.InstanceId)
            Set-StateProperty $State LastRegistryMode ([pscustomobject]@{ Width=$width; Height=$height; Frequency=$frequency; BitsPerPel=$bitsPerPel })
            $disposition = 'PersistedForNextActivation'
            $verification = 'EnumRegistrySettings'
        }
        Set-StateProperty $State LastModeWrite ([pscustomobject]@{
            Disposition=$disposition; Width=$width; Height=$height; Frequency=$frequency
            DeviceName=$(if ($ResidualDisplay) { $ResidualDisplay.DeviceName } else { $State.DeviceNameBeforeDisable })
            Verification=$verification; ProblemCodeAfter=22; CompletedAt=(Get-Date).ToString('o')
        })
        Set-StateProperty $State MonitorDisabledByTool $true
        Set-StateProperty $State Phase $(if ($disposition -eq 'AppliedNow') { 'Code22ModeAppliedNow' } else { 'Code22RegistryModePersisted' })
        Set-StateProperty $State LastError $null
        Write-RecoveryState $State
        [pscustomobject]@{
            ResultType='ModeWrite'; Disposition=$disposition; AppliedNow=($disposition -eq 'AppliedNow'); RegistryUpdated=$true
            Verified=$true; Verification=$verification
            Width=$width; Height=$height; Frequency=$frequency; ProblemCodeAfter=22
        } | ConvertTo-Json -Compress
    } catch {
        Set-StateProperty $State Phase 'Code22ModeWriteFailed'
        Set-StateProperty $State LastError $_.Exception.Message
        Write-RecoveryState $State
        throw
    }
}

function Enable-SavedMonitor {
    $state = Read-RecoveryState
    if ($null -eq $state) { throw "No saved state file was found: $StatePath" }
    Write-RecoveryState $state
    $state | Add-Member NoteProperty LastRestoreAttempt (Get-Date).ToString('o') -Force
    $state | Add-Member NoteProperty Phase 'RestorePending' -Force
    Write-RecoveryState $state

    $device = Get-PnpDevice -InstanceId $state.InstanceId -ErrorAction SilentlyContinue
    if ($null -eq $device -or $device.Status -ne 'OK') {
        Write-Host "Enabling monitor: $($state.InstanceId)"
        Enable-PnpDevice -InstanceId $state.InstanceId -Confirm:$false
        Start-Sleep -Seconds 3
        $device = Get-PnpDevice -InstanceId $state.InstanceId -ErrorAction SilentlyContinue
        if ($null -eq $device -or $device.Status -ne 'OK') {
            $state | Add-Member NoteProperty LastError 'Windows did not report the monitor as enabled.' -Force
            Write-RecoveryState $state
            throw 'Windows did not report the monitor as enabled. Recovery data was preserved.'
        }
    }

    Write-Host 'Restoring the saved baseline resolution...'
    if (-not (Restore-OriginalMode -State $state)) {
        $state | Add-Member NoteProperty LastError 'The baseline display mode could not be verified after restoration.' -Force
        Write-RecoveryState $state
        throw 'The monitor is enabled, but its baseline display mode could not be restored. Recovery data was preserved.'
    }

    Set-StateProperty $state OperationKind 'Restored'
    Set-StateProperty $state Phase 'Restored'
    Set-StateProperty $state MonitorDisabledByTool $false
    Set-StateProperty $state LastAppliedMode ([pscustomobject]@{
        Width = [int]$state.Baseline.Width
        Height = [int]$state.Baseline.Height
        Frequency = [int]$state.Baseline.Frequency
    })
    Set-StateProperty $state LastKnownMode $state.LastAppliedMode
    Set-StateProperty $state LastError $null
    Write-RecoveryState $state
    Write-Host ('Restored {0}x{1} @{2}Hz.' -f $state.Baseline.Width, $state.Baseline.Height, $state.Baseline.Frequency) -ForegroundColor Green
}

$operationMutex = $null
$operationLockTaken = $false
if ($Action -notin @('DryRun', 'DryRun1440', 'DryRun1920', 'Status')) {
    $operationMutex = New-Object Threading.Mutex($false, 'Global\MonitorModeConsole.DisplayOperation')
    try {
        $operationLockTaken = $operationMutex.WaitOne(0)
    } catch [Threading.AbandonedMutexException] {
        $operationLockTaken = $true
    }
    if (-not $operationLockTaken) {
        $operationMutex.Dispose()
        throw 'Another display operation is already running. This request was not queued.'
    }
    if (-not (Test-Path -LiteralPath $StateRoot)) {
        New-Item -ItemType Directory -Path $StateRoot -Force | Out-Null
    }
    if (-not (Test-Path -LiteralPath $StatePath) -and (Test-Path -LiteralPath $legacyStatePath)) {
        Copy-Item -LiteralPath $legacyStatePath -Destination $StatePath -Force
    }
}

try {
if ($Action -eq 'Status') {
    $saved = $null
    $stateError = $null
    try { $saved = Read-RecoveryState -ReadOnly } catch { $stateError = $_.Exception.Message }
    $active = @(Get-ActiveMonitorChoices)
    $nvidia = @($active | Where-Object { $_.AdapterName -match 'NVIDIA' })
    foreach ($display in $nvidia) {
        $displayDeviceState = Get-MonitorDeviceState -InstanceId $display.InstanceId
        $display | Add-Member NoteProperty ProblemCode $displayDeviceState.ProblemCode -Force
        $display | Add-Member NoteProperty ProblemCodeKnown $displayDeviceState.ProblemCodeKnown -Force
        $display | Add-Member NoteProperty PnpDisabled $displayDeviceState.Disabled -Force
        $native = Get-NativePanelSize -InstanceId $display.InstanceId
        $display | Add-Member NoteProperty Supports1280 (Get-ModeCapability $display 1280 880) -Force
        $display | Add-Member NoteProperty Supports1440 (Get-ModeCapability $display 1440 1080) -Force
        $display | Add-Member NoteProperty SupportsNative $(
            $null -ne ([MonitorMode.NativeDisplay]::GetModes($display.DeviceName, $display.CurrentWidth, $display.CurrentHeight) |
                Where-Object { $_.Frequency -eq $display.CurrentFrequency } | Select-Object -First 1)
        ) -Force
        $display | Add-Member NoteProperty Supports1920 (Get-ModeCapability $display 1920 1440) -Force
        $display | Add-Member NoteProperty NativeWidth $(if ($native) { $native.Width } else { 0 }) -Force
        $display | Add-Member NoteProperty NativeHeight $(if ($native) { $native.Height } else { 0 }) -Force
        $display | Add-Member NoteProperty Allows1920 $(
            $native -and $native.Width -ge 1920 -and $native.Height -ge 1440 -and
            (Get-ModeCapability $display 1920 1440)
        ) -Force
    }
    $deviceStatus = $null
    $targetPnpDisabled = $false
    $targetMissing = $false
    $targetError = $false
    if ($saved) {
        $savedDevice = Get-PnpDevice -InstanceId $saved.InstanceId -Class Monitor -PresentOnly -ErrorAction SilentlyContinue
        $deviceStatus = if ($savedDevice) { [string]$savedDevice.Status } else { 'Missing' }
        $problemCode = $null
        if ($savedDevice) {
            try { $problemCode = [int](Get-PnpDeviceProperty -InstanceId $saved.InstanceId -KeyName 'DEVPKEY_Device_ProblemCode' -ErrorAction Stop).Data } catch { }
        }
        $targetMissing = $null -eq $savedDevice
        $targetPnpDisabled = -not $targetMissing -and $problemCode -eq 22
        $targetError = -not $targetMissing -and -not $targetPnpDisabled -and $deviceStatus -ne 'OK'
    }
    $hasResidualActivePath = $false
    $hasOfflineModeSnapshot = $false
    $disabledModeWriteKind = 'Unavailable'
    if ($saved) {
        $residualDisplay = @($nvidia | Where-Object { $_.InstanceId -eq $saved.InstanceId } | Select-Object -First 1)
        $hasResidualActivePath = $residualDisplay.Count -gt 0
        $hasOfflineModeSnapshot = Test-OfflineModeSnapshot $saved
        if ($targetPnpDisabled) {
            if ($hasResidualActivePath) { $disabledModeWriteKind = 'ImmediateResidualPath' }
            elseif ($hasOfflineModeSnapshot) { $disabledModeWriteKind = 'PersistentRegistry' }
            else { $disabledModeWriteKind = 'UnavailableLegacyState' }
        }
    }
    [pscustomobject]@{
        HasSavedState = $null -ne $saved; RestoreAvailable = $null -ne $saved
        StateValid = $null -eq $stateError; StateError = $stateError; StatePath = $StatePath
        ActiveDisplayCount = $active.Count; NvidiaDisplays = $nvidia; SavedState = $saved
        DeviceStatus = $deviceStatus; TargetPnpDisabled = $targetPnpDisabled
        TargetMissing = $targetMissing; TargetError = $targetError
        DeviceDisabled = $targetPnpDisabled
        HasResidualActivePath = $hasResidualActivePath; HasOfflineModeSnapshot = $hasOfflineModeSnapshot
        DisabledModeWriteAvailable = $targetPnpDisabled -and ($hasResidualActivePath -or $hasOfflineModeSnapshot)
        DisabledModeWriteKind = $disabledModeWriteKind
    } | ConvertTo-Json -Depth 8 -Compress
    return
}
if ($Action -eq 'Restore') {
    Enable-SavedMonitor
    return
}

$state = Read-RecoveryState
if ($Action -eq 'Enable') {
    if ($null -eq $state) { throw 'No saved monitor identity is available.' }
    Enable-MonitorOnly -State $state
    Write-Host 'The monitor is enabled.' -ForegroundColor Green
    return
}

$modeActions = @('Apply', 'Set1440', 'Set1920', 'SetNative')
$monitors = @(Get-ActiveMonitorChoices)
$nvidiaMonitors = @($monitors | Where-Object { $_.AdapterName -match 'NVIDIA' })
$selected = $null
if ($TargetInstanceId) {
    $selected = $nvidiaMonitors | Where-Object { $_.InstanceId -eq $TargetInstanceId } | Select-Object -First 1
} elseif ($nvidiaMonitors.Count -eq 1) {
    $selected = $nvidiaMonitors[0]
} elseif (-not $NonInteractive -and $nvidiaMonitors.Count -gt 0) {
    Write-Host 'Active monitors connected to NVIDIA adapters:' -ForegroundColor Cyan
    $selected = Select-FromList -Items $nvidiaMonitors -Prompt 'Select the monitor number'
}

if ($null -eq $selected) {
    if ($Action -in $modeActions -and $state -and $TargetInstanceId -eq $state.InstanceId) {
        $savedDeviceState = Get-MonitorDeviceState -InstanceId $state.InstanceId
        if (-not $savedDeviceState.Disabled) {
            if ($savedDeviceState.Missing) { throw 'The saved monitor is missing, so its resolution cannot be changed.' }
            throw ('The saved monitor is not in a confirmed disabled state (status: {0}).' -f $savedDeviceState.Status)
        }
        Set-ModeWhileCode22 -State $state -RequestedAction $Action -ResidualDisplay $null
        return
    }
    throw 'No active NVIDIA monitor could be selected.'
}

if ($Action -eq 'Disable') {
    if ($monitors.Count -eq 1 -and -not $AllowSoleDisplayDisable) {
        throw 'This is the only active display. Explicit confirmation is required.'
    }
    $state = Ensure-RecoveryBaseline -Display $selected
    $snapshotDisplay = @(Get-ActiveMonitorChoices) | Where-Object { $_.InstanceId -eq $selected.InstanceId } | Select-Object -First 1
    if (-not $snapshotDisplay) { throw 'The monitor display path disappeared before its disable snapshot could be captured.' }
    Save-DisableSnapshot -State $state -Display $snapshotDisplay
    Set-StateProperty $state LastKnownMode ([pscustomobject]@{ Width=[int]$snapshotDisplay.CurrentWidth; Height=[int]$snapshotDisplay.CurrentHeight; Frequency=[int]$snapshotDisplay.CurrentFrequency })
    Set-StateProperty $state ActiveDisplayCountBeforeDisable ([int]$monitors.Count)
    Set-StateProperty $state WasSoleDisplayAtDisable ($monitors.Count -eq 1)
    Set-StateProperty $state OperationKind 'DeviceDisable'
    Set-StateProperty $state Phase 'DisablePending'
    Write-RecoveryState $state
    try {
        Disable-ConfirmedMonitorDevice -InstanceId $selected.InstanceId
        Set-StateProperty $state MonitorDisabledByTool $true
        Set-StateProperty $state Phase 'DeviceDisabled'
        Set-StateProperty $state LastError $null
        Write-RecoveryState $state
        Write-Host 'The monitor device is disabled.' -ForegroundColor Green
        return
    } catch {
        Set-StateProperty $state Phase 'DisableFailed'
        Set-StateProperty $state LastError $_.Exception.Message
        Write-RecoveryState $state
        throw
    }
}

if ($Action -in $modeActions -and $selected) {
    $selectedDeviceState = Get-MonitorDeviceState -InstanceId $selected.InstanceId
    if ($selectedDeviceState.Disabled) {
        if (-not $state -or $state.InstanceId -ne $selected.InstanceId) { throw 'The disabled monitor has no matching recovery state and cannot be modified safely.' }
        Set-ModeWhileCode22 -State $state -RequestedAction $Action -ResidualDisplay $selected
        return
    }
    if ($selectedDeviceState.Missing -or -not $selectedDeviceState.ProblemCodeKnown -or $selectedDeviceState.Status -ne 'OK') {
        throw 'The monitor PnP state could not be confirmed as enabled, so no resolution change was attempted.'
    }
}

if ($Action -eq 'SetNative') {
    $state = Ensure-RecoveryBaseline -Display $selected
    $TargetWidth = [int]$state.Baseline.Width
    $TargetHeight = [int]$state.Baseline.Height
    $targetFrequency = [int]$state.Baseline.Frequency
} else {
    $targetFrequency = [int]$selected.CurrentFrequency
}

$availableModes = @([MonitorMode.NativeDisplay]::GetModes($selected.DeviceName, $TargetWidth, $TargetHeight))
$sameFrequencyMode = $availableModes | Where-Object { $_.Frequency -eq $targetFrequency } | Select-Object -First 1

Write-Host ('Selected monitor : {0}' -f $selected.MonitorName)
Write-Host ('Current mode     : {0}x{1} @{2}Hz' -f $selected.CurrentWidth, $selected.CurrentHeight, $selected.CurrentFrequency)
Write-Host ('Requested mode   : {0}x{1} @{2}Hz' -f $TargetWidth, $TargetHeight, $targetFrequency)
if (-not $sameFrequencyMode) {
    throw ('{0}x{1} at {2}Hz is not an existing driver mode. No change was made.' -f $TargetWidth, $TargetHeight, $targetFrequency)
}

if ($Action -in @('DryRun', 'DryRun1440', 'DryRun1920')) {
    Write-Host 'Dry run passed. The requested mode exists and no system changes were made.' -ForegroundColor Green
    return
}

if ($Action -eq 'Set1920') {
    $native = Get-NativePanelSize -InstanceId $selected.InstanceId
    if ($null -eq $native -or $native.Width -lt 1920 -or $native.Height -lt 1440) {
        throw '1920x1440 is blocked: this monitor is not a native 1440p-or-higher panel.'
    }
}

$state = Ensure-RecoveryBaseline -Display $selected
Set-StateProperty $state OperationKind $(
    if ($Action -eq 'Apply') { 'ModeSwitch1280' }
    elseif ($Action -eq 'Set1440') { 'ModeSwitch1440' }
    elseif ($Action -eq 'Set1920') { 'ModeSwitch1920' }
    else { 'ModeSwitchNative' }
)
Set-StateProperty $state Phase 'ModeChangePending'
Set-StateProperty $state MonitorDisabledByTool $false
Set-StateProperty $state LastError $null
Write-RecoveryState $state

try {
    Set-VerifiedDisplayMode $selected $TargetWidth $TargetHeight $targetFrequency
    Set-StateProperty $state LastAppliedMode ([pscustomobject]@{
        Width = $TargetWidth; Height = $TargetHeight; Frequency = $targetFrequency
    })
    Set-StateProperty $state LastKnownMode $state.LastAppliedMode
    Set-StateProperty $state Phase 'ModeApplied'
    Write-RecoveryState $state
    Write-Host ('Resolution changed to {0}x{1} @{2}Hz. The monitor remains enabled.' -f $TargetWidth, $TargetHeight, $targetFrequency) -ForegroundColor Green
} catch {
    Set-StateProperty $state Phase 'ModeChangeFailed'
    Set-StateProperty $state LastError $_.Exception.Message
    Write-RecoveryState $state
    throw
}
} finally {
    if ($operationLockTaken -and $operationMutex) { $operationMutex.ReleaseMutex() }
    if ($operationMutex) { $operationMutex.Dispose() }
}
