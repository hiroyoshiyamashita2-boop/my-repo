@description('Azure region')
param location string

@description('Target virtual machine name')
param vmName string

resource vm 'Microsoft.Compute/virtualMachines@2023-09-01' existing = {
  name: vmName
}

resource postReboot 'Microsoft.Compute/virtualMachines/runCommands@2023-09-01' = {
  name: 'ConfigureOsState-PostReboot'
  parent: vm
  location: location
  properties: {
    source: {
      script: '''
#--------------------------------------------------
# Log setup
#--------------------------------------------------
$logDir  = "C:\WindowsAzure\Logs"
$logFile = "$logDir\PostReboot.log"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
Start-Transcript -Path $logFile -Append

Write-Output "=== POST-REBOOT START ==="
Write-Output "Timestamp (UTC): $(Get-Date -Format u)"
Write-Output "Computer       : $env:COMPUTERNAME"

#--------------------------------------------------
# Pending reboot check
#--------------------------------------------------
$pending = $false

$paths = @(
  'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
  'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
)

foreach ($path in $paths) {
  if (Test-Path $path) {
    $pending = $true
    Write-Output "Pending reboot detected: $path"
  }
}

if ($pending) {
  Write-Output "WARNING: System still requires reboot."
} else {
  Write-Output "No pending reboot detected."
}

#--------------------------------------------------
# Completion marker (C:\WindowsAzure\Logs)
#--------------------------------------------------
$markerFile = "$logDir\MasterVmCompleted.txt"
Set-Content `
  -Path $markerFile `
  -Value "Master VM provisioning completed at $(Get-Date -Format u)"

Write-Output "Completion marker created: $markerFile"

Write-Output "Post-reboot configuration completed successfully."
Stop-Transcript
'''
    }
  }
}
