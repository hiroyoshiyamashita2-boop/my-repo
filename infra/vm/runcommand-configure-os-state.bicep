@description('Azure region')
param location string

@description('Target virtual machine name')
param vmName string

@description('Local administrator username')
param adminUsername string = 'avdlocaladmin'

@secure()
@description('Local administrator password')
param adminPassword string

resource vm 'Microsoft.Compute/virtualMachines@2023-09-01' existing = {
  name: vmName
}

resource configureOsStateRunCommand 'Microsoft.Compute/virtualMachines/runCommands@2023-09-01' = {
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

$logDir  = "C:\WindowsAzure\Logs"
$logFile = "$logDir\ConfigureOsState-PreReboot.log"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
Start-Transcript -Path $logFile -Append

Write-Output "=== PRE-REBOOT PHASE START ==="
Write-Output "Timestamp (UTC): $(Get-Date -Format u)"
Write-Output "Target VM      : $env:COMPUTERNAME"
Write-Output "Target User    : $adminUsername"

net user $adminUsername $adminPassword
Write-Output "Password reset completed."

Set-ItemProperty `
 -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' `
 -Name 'PagingFiles' `
 -Value 'C:\pagefile.sys 4096 8192'

Remove-ItemProperty `
 -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' `
 -Name 'TempPageFile' `
 -ErrorAction SilentlyContinue

Write-Output "Paging file configured."

# Windows Update
if (-not (Get-Module -ListAvailable PSWindowsUpdate)) {
  Install-PackageProvider -Name NuGet -Force
  Install-Module PSWindowsUpdate -Force -Confirm:$false
}
Import-Module PSWindowsUpdate
Install-WindowsUpdate -AcceptAll -IgnoreReboot -Verbose

Write-Output "Rebooting system..."
Stop-Transcript
Restart-Computer -Force
'''
    }
  }
}
