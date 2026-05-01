@description('Azure region')
param location string

@description('Target virtual machine name')
param vmName string

resource vm 'Microsoft.Compute/virtualMachines@2023-09-01' existing = {
  name: vmName
}

resource postRebootUpdateCheck 'Microsoft.Compute/virtualMachines/runCommands@2023-09-01' = {
  name: 'ConfigureOsState-PostReboot'
  parent: vm
  location: location
  properties: {
    source: {
      script: '''
$logDir  = "C:\WindowsAzure\Logs"
$logFile = "$logDir\ConfigureOsState-PostReboot.log"
Start-Transcript -Path $logFile -Append

Write-Output "=== POST-REBOOT PHASE START ==="
Write-Output "Timestamp (UTC): $(Get-Date -Format u)"

Import-Module PSWindowsUpdate
$pending = Get-WindowsUpdate

if ($pending.Count -eq 0) {
  Write-Output "Windows Update completed successfully."
} else {
  Write-Output "Pending updates detected:"
  $pending | Format-Table -AutoSize
}

Write-Output "=== POST-REBOOT PHASE END ==="
Stop-Transcript
'''
    }
  }
}
