@description('Azure region')
param location string

@description('Target virtual machine name')
param vmName string

@secure()
@description('Local administrator password')
param adminPassword string

// 固定ローカル管理者名
var adminUsername = 'avdlocaladmin'

resource vm 'Microsoft.Compute/virtualMachines@2023-09-01' existing = {
  name: vmName
}

resource preReboot 'Microsoft.Compute/virtualMachines/runCommands@2023-09-01' = {
  name: 'ConfigureOsState-PreReboot'
  parent: vm
  location: location
  properties: {
    parameters: [
      {
        name: 'adminUsername'
        value: adminUsername
      }
      {
        name: 'adminPassword'
        value: adminPassword
      }
    ]
    source: {
      script: '''
param(
  [string]$adminUsername,
  [string]$adminPassword
)

#--------------------------------------------------
# Log setup
#--------------------------------------------------
$logDir  = "C:\WindowsAzure\Logs"
$logFile = "$logDir\PreReboot.log"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
Start-Transcript -Path $logFile -Append

Write-Output "=== PRE-REBOOT START ==="
Write-Output "Timestamp (UTC): $(Get-Date -Format u)"
Write-Output "Computer       : $env:COMPUTERNAME"
Write-Output "User           : $adminUsername"

#--------------------------------------------------
# Local administrator password reset
#--------------------------------------------------
net user $adminUsername $adminPassword
Write-Output "Local administrator password updated."

#--------------------------------------------------
# Paging file DISABLE & DELETE（RunCommand 安定版）
#--------------------------------------------------
Write-Output "Disabling and removing paging file..."

# 自動管理を無効化
wmic computersystem where name="%COMPUTERNAME%" set AutomaticManagedPagefile=False | Out-Null

# PagingFiles を完全に無効化（1行指定）
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' -Name 'PagingFiles' -Value @()

# 一時ページング設定を削除
Remove-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' -Name 'TempPageFile' -ErrorAction SilentlyContinue

# pagefile.sys 実体削除
if (Test-Path 'C:\pagefile.sys') {
  Remove-Item 'C:\pagefile.sys' -Force
  Write-Output "pagefile.sys removed."
} else {
  Write-Output "No pagefile.sys found."
}

Write-Output "Paging file configuration cleared."

#--------------------------------------------------
# Windows Update (PSWindowsUpdate / PowerShell 5.1)
#--------------------------------------------------
Write-Output "Starting Windows Update using PSWindowsUpdate (PowerShell 5.1)..."

$wuScript = @'
$ProgressPreference = "SilentlyContinue"

if (-not (Get-Module -ListAvailable PSWindowsUpdate)) {
  Install-PackageProvider -Name NuGet -Force
  Install-Module PSWindowsUpdate -Force -Confirm:$false
}

Import-Module PSWindowsUpdate
Install-WindowsUpdate -AcceptAll -IgnoreReboot -Verbose
'@

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command $wuScript

Write-Output "PSWindowsUpdate completed."

#--------------------------------------------------
# Windows Update (GUI equivalent: UsoClient)
#--------------------------------------------------
Write-Output "Triggering Windows Update via UsoClient (GUI equivalent)..."

usoclient StartScan
Start-Sleep -Seconds 30

usoclient StartDownload
Start-Sleep -Seconds 30

usoclient StartInstall

Write-Output "UsoClient update commands issued."

#--------------------------------------------------
# Reboot
#--------------------------------------------------
Write-Output "Rebooting system..."
Stop-Transcript
Restart-Computer -Force
'''
    }
  }
}
