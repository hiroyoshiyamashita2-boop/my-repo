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

/*
 * -------------------------------------------------
 * RunCommand: Configure OS State
 * - Short running
 * - No reboot
 * - No Windows Update
 * -------------------------------------------------
 */
resource configureOs 'Microsoft.Compute/virtualMachines/runCommands@2023-09-01' = {
  name: 'ConfigureOsState'
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

$ErrorActionPreference = 'Stop'

#==================================================
# Log setup
#==================================================
$logDir  = "C:\\WindowsAzure\\Logs"
$logFile = "$logDir\\ConfigureOsState.log"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
Start-Transcript -Path $logFile -Append

Write-Output "=== CONFIGURE OS STATE START ==="
Write-Output "Timestamp (UTC): $(Get-Date -Format u)"
Write-Output "Computer       : $env:COMPUTERNAME"

#==================================================
# Local administrator password reset
#==================================================
net user $adminUsername $adminPassword
Write-Output "Local administrator password updated."

#==================================================
# Disable paging file (CIM 正式手法)
#==================================================
Write-Output "Disabling automatic paging file management..."

Get-CimInstance -ClassName Win32_ComputerSystem -Namespace root\\cimv2 |
  Set-CimInstance -Property @{ AutomaticManagedPagefile = $false }

Set-ItemProperty `
  -Path 'HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Memory Management' `
  -Name 'PagingFiles' `
  -Value @()

Remove-ItemProperty `
  -Path 'HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Memory Management' `
  -Name 'TempPageFile' `
  -ErrorAction SilentlyContinue

if (Test-Path 'C:\\pagefile.sys') {
  Remove-Item 'C:\\pagefile.sys' -Force
  Write-Output "pagefile.sys removed."
} else {
  Write-Output "No pagefile.sys found."
}

Write-Output "Paging file configuration completed."

#==================================================
# End
#==================================================
Write-Output "=== CONFIGURE OS STATE COMPLETED ==="
Stop-Transcript
'''
    }
  }
}
