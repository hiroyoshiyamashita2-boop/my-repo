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

Write-Output "=== POST-REBOOT WINDOWS UPDATE VALIDATION ==="
Write-Output "Timestamp (UTC): $(Get-Date -Format u)"
Write-Output "Computer       : $env:COMPUTERNAME"

#--------------------------------------------------
# Pending reboot detection function
#--------------------------------------------------
function Test-PendingReboot {

  $paths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
  )

  foreach ($path in $paths) {
    if (Test-Path $path) {
      Write-Output "Pending reboot detected: $path"
      return $true
    }
  }

  $pfro = Get-ItemProperty `
    'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' `
    -Name PendingFileRenameOperations `
    -ErrorAction SilentlyContinue

  if ($pfro) {
    Write-Output "PendingFileRenameOperations detected."
    return $true
  }

  return $false
}

#--------------------------------------------------
# Windows Update remaining check
#--------------------------------------------------
try {
  Import-Module PSWindowsUpdate -ErrorAction Stop
} catch {
  Write-Error "PSWindowsUpdate module not available."
  Stop-Transcript
  exit 1
}

Write-Output "Checking remaining Windows Updates..."

$remainingUpdates = Get-WindowsUpdate -MicrosoftUpdate -AcceptAll -IgnoreReboot -Verbose

#--------------------------------------------------
# Strict validation
#--------------------------------------------------
$pendingReboot = Test-PendingReboot

if ($pendingReboot) {
  Write-Error "System still requires reboot. Windows Update NOT completed."
  Stop-Transcript
  exit 1
}

if ($remainingUpdates.Count -gt 0) {
  Write-Error "Remaining Windows Updates detected. Count: $($remainingUpdates.Count)"
  Stop-Transcript
  exit 1
}

#--------------------------------------------------
# Completion marker (success only)
#--------------------------------------------------
$markerFile = "$logDir\MasterVmCompleted.txt"
Set-Content `
  -Path $markerFile `
  -Value "Master VM provisioning completed successfully at $(Get-Date -Format u)"

Write-Output "Completion marker created: $markerFile"
Write-Output "POST-REBOOT VALIDATION SUCCESSFUL"

Stop-Transcript
exit 0
'''
    }
  }
}
