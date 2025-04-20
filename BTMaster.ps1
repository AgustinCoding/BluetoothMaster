<#
.SYNOPSIS
  BluetoothMaster - Bluetooth Control Tool for Windows

.DESCRIPTION
  Interactive PowerShell script to safely manage Bluetooth adapters

.NOTES
  Version: 3.6
  Author: AgustinCoding
  Modified: 20/04/2025
#>

function Pause {
    Write-Host "Press Enter to continue..."
    $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") | Out-Null
}

function Test-Admin {
    $currentUser = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    Write-Host "Requesting elevation of privileges..." -ForegroundColor Yellow
    Start-Sleep -Seconds 2
    
    $scriptPath = if ($MyInvocation.MyCommand.Path) { 
        $MyInvocation.MyCommand.Path 
    } else { 
        $PSCommandPath 
    }
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" -Verb RunAs
    exit
}

$Global:LogFile = Join-Path $PSScriptRoot "BluetoothMaster.log"
$Global:ConfigFile = Join-Path $PSScriptRoot "BluetoothMaster.config.json"

function Write-Log {
    param (
        [string]$Message,
        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    Add-Content -Path $Global:LogFile -Value $logEntry
    
    $color = switch ($Level) {
        "INFO" { "White" }
        "WARNING" { "Yellow" }
        "ERROR" { "Red" }
        "SUCCESS" { "Green" }
        default { "White" }
    }
    
    Write-Host $logEntry -ForegroundColor $color
}

function Initialize-Config {
    if (Test-Path $Global:ConfigFile) {
        try {
            return Get-Content -Path $Global:ConfigFile -Raw | ConvertFrom-Json
        }
        catch {
            Write-Log "Error loading configuration: $_" -Level "ERROR"
            return New-DefaultConfig
        }
    }
    else {
        return New-DefaultConfig
    }
}

function New-DefaultConfig {
    $config = @{
        AutoReconnect = $false
        DefaultDevice = ""
        Theme = "Default"
    }
    
    $config | ConvertTo-Json | Set-Content -Path $Global:ConfigFile
    return $config
}

function Save-Config {
    param ([PSCustomObject]$Config)
    $Config | ConvertTo-Json | Set-Content -Path $Global:ConfigFile
}

$Config = Initialize-Config

function Show-Menu {
    Clear-Host
    Write-Host "===============================" -ForegroundColor Cyan
    Write-Host "     BluetoothMaster 3600" -ForegroundColor Green
    Write-Host "==============================="
    Write-Host "1. Enable Bluetooth"
    Write-Host "2. Disable Bluetooth"
    Write-Host "3. List adapters"
    Write-Host "4. Restart adapter"
    Write-Host "5. Remove device"
    Write-Host "6. Reset services"
    Write-Host "7. Show hidden devices"
    Write-Host "8. Open settings"
    Write-Host "9. Backup configuration"
    Write-Host "0. Exit"
    Write-Host "-------------------------------"
}

function Get-BluetoothAdapter {
    try {
        $adapters = Get-PnpDevice -Class Bluetooth -ErrorAction Stop | Where-Object { $_.Status -eq "OK" }
        return $adapters
    }
    catch {
        Write-Log "Error searching for adapters: $_" -Level "ERROR"
        return $null
    }
}

function Enable-Bluetooth {
    $adapters = Get-PnpDevice -Class Bluetooth
    foreach ($adapter in $adapters) {
        try {
            Enable-PnpDevice -InstanceId $adapter.InstanceId -Confirm:$false -ErrorAction Stop
            Write-Log "Bluetooth enabled: $($adapter.Name)" -Level "SUCCESS"
        }
        catch {
            Write-Log "Error enabling $($adapter.Name): $_" -Level "ERROR"
        }
    }
}

function Disable-Bluetooth {
    $adapters = Get-BluetoothAdapter
    foreach ($adapter in $adapters) {
        try {
            Disable-PnpDevice -InstanceId $adapter.InstanceId -Confirm:$false -ErrorAction Stop
            Write-Log "Bluetooth disabled: $($adapter.Name)" -Level "INFO"
        }
        catch {
            Write-Log "Error disabling $($adapter.Name): $_" -Level "ERROR"
        }
    }
}

function Restart-Bluetooth {
    Disable-Bluetooth
    Start-Sleep -Seconds 3
    Enable-Bluetooth
    Write-Log "Restart completed" -Level "SUCCESS"
}

function Remove-BluetoothDevice {
    param ([string]$DeviceName)
    
    $devices = Get-PnpDevice | Where-Object { $_.FriendlyName -like "*$DeviceName*" -and ($_.Class -eq "Bluetooth" -or $_.Class -eq "BTH") }
    
    if ($devices.Count -gt 1) {
        Write-Host "Found devices:"
        for ($i = 0; $i -lt $devices.Count; $i++) {
            Write-Host "$($i+1). $($devices[$i].FriendlyName)"
        }
        $selection = Read-Host "Select device (or 'C' to cancel)"
        if ($selection -eq "C") { return }
        $index = [int]$selection - 1
        $device = $devices[$index]
    }
    else {
        $device = $devices
    }
    
    try {
        Disable-PnpDevice -InstanceId $device.InstanceId -Confirm:$false
        Remove-PnpDevice -InstanceId $device.InstanceId -Confirm:$false
        Write-Log "Device removed: $($device.FriendlyName)" -Level "SUCCESS"
    }
    catch {
        Write-Log "Error removing device: $_" -Level "ERROR"
    }
}

function Reset-BluetoothStack {
    $services = @("bthserv", "DeviceAssociationService", "DeviceInstall")
    
    foreach ($svc in $services) {
        try {
            Get-Service -Name $svc -ErrorAction SilentlyContinue | ForEach-Object {
                Stop-Service $_.Name -Force
                Start-Service $_.Name
                Write-Log "Service $($_.Name) restarted" -Level "SUCCESS"
            }
        }
        catch {
            Write-Log "Error restarting service ${svc}: $_" -Level "ERROR"
        }
    }
}

function Show-HiddenBluetoothDevices {
    try {
        $devices = Get-PnpDevice -Class Bluetooth -Status Unknown, Error, Degraded
        if ($devices) {
            $devices | Format-Table FriendlyName, Status, InstanceId -AutoSize
        }
        else {
            Write-Host "No hidden devices found" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Log "Error searching for devices: $_" -Level "ERROR"
    }
    Pause
}

function Open-BluetoothSettings {
    Start-Process ms-settings:bluetooth
}

function Backup-BluetoothConfig {
    $backupFolder = Join-Path $PSScriptRoot "Backups"
    if (-not (Test-Path $backupFolder)) { New-Item -Path $backupFolder -ItemType Directory | Out-Null }
    
    $date = Get-Date -Format "yyyy-MM-dd_HH-mm"
    $backupFile = Join-Path $backupFolder "BluetoothConfig_$date.reg"
    
    try {
        reg export "HKLM\SYSTEM\CurrentControlSet\Services\BTHPORT" $backupFile /y | Out-Null
        Write-Log "Backup created: $backupFile" -Level "SUCCESS"
    }
    catch {
        Write-Log "Error creating backup: $_" -Level "ERROR"
    }
}

if (-not (Test-Path $Global:LogFile)) { New-Item -Path $Global:LogFile -Force | Out-Null }
Write-Log "Session started" -Level "INFO"

do {
    Show-Menu
    $choice = Read-Host "Select an option"
    
    switch ($choice) {
        "1" { Enable-Bluetooth }
        "2" { Disable-Bluetooth }
        "3" { 
            Get-BluetoothAdapter | Format-Table Name, Status, InstanceId -AutoSize
            Pause
        }
        "4" { Restart-Bluetooth }
        "5" { 
            $name = Read-Host "Enter device name"
            Remove-BluetoothDevice -DeviceName $name
        }
        "6" { Reset-BluetoothStack }
        "7" { Show-HiddenBluetoothDevices }
        "8" { Open-BluetoothSettings }
        "9" { Backup-BluetoothConfig }
        "0" { Write-Log "Session ended" -Level "INFO"; break }
        default { Write-Host "Invalid option" -ForegroundColor Red }
    }
    
    if ($choice -ne "0") { Pause }
} while ($choice -ne "0")