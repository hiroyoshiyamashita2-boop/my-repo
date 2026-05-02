@description('Azure region')
param location string

@description('Target virtual machine name')
param vmName string

@secure()
@description('Local administrator password')
param adminPassword string

var adminUsername = 'avdlocaladmin'

resource vm 'Microsoft.Compute/virtualMachines@2023-09-01' existing = {
  name: vmName
}

//
// -------------------------------------------------
// Pre-Reboot RunCommand
// -------------------------------------------------
//
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

#==================================================
# Log setup
#==================================================
$logDir  = "C:\WindowsAzure\Logs"
$logFile = "$logDir\PreReboot.log"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
Start-Transcript -Path $logFile -Append

Write-Output "=== PRE-REBOOT CONFIGURATION START ==="
Write-Output "Timestamp (UTC): $(Get-Date -Format u)"
Write-Output "Computer       : $env:COMPUTERNAME"

#==================================================
# Local administrator password reset
#==================================================
net user $adminUsername $adminPassword
Write-Output "Local administrator password updated."

#==================================================
# Paging file DISABLE & DELETE (WMIC-free)
#==================================================
Write-Output "Disabling automatic paging file management..."

Set-CimInstance `
  -Namespace root\cimv2 `
  -ClassName Win32_ComputerSystem `
  -Property @{ AutomaticManagedPagefile = $false }

Set-ItemProperty `
  -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' `
  -Name 'PagingFiles' `
  -Value @()

Remove-ItemProperty `
  -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' `
  -Name 'TempPageFile' `
  -ErrorAction SilentlyContinue

if (Test-Path 'C:\pagefile.sys') {
  Remove-Item 'C:\pagefile.sys' -Force
  Write-Output "pagefile.sys removed."
} else {
  Write-Output "No pagefile.sys found."
}

Write-Output "Paging file configuration completed."

#==================================================
# Windows Update (Ignore Reboot)
#==================================================
Write-Output "Starting Windows Update (IgnoreReboot)..."

if (-not (Get-Module -ListAvailable PSWindowsUpdate)) {
  Install-PackageProvider -Name NuGet -Force
  Install-Module PSWindowsUpdate -Force -Confirm:$false
}

Import-Module PSWindowsUpdate
Install-WindowsUpdate -AcceptAll -IgnoreReboot -Verbose

Write-Output "Windows Update execution finished (reboot may be required)."

#==================================================
# End
#==================================================
Stop-Transcript
'''
    }
  }
}

//
// -------------------------------------------------
// ARM-controlled VM Restart (Action)
// -------------------------------------------------
//
resource rebootVm 'Microsoft.Compute/virtualMachines/restart@2023-09-01' = {
  name: 'restart'
  parent: vm
  dependsOn: [
    preReboot
  ]
}
