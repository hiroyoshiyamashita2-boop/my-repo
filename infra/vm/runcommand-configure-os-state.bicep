@description('Azure region')
param location string

@description('Target virtual machine name')
param vmName string

@description('Local administrator username (must already exist)')
param adminUsername string = 'avdlocaladmin'

@secure()
@description('New password for local administrator user')
param adminPassword string

resource vm 'Microsoft.Compute/virtualMachines@2023-09-01' existing = {
  name: vmName
}

resource configureOsStateRunCommand 'Microsoft.Compute/virtualMachines/runCommands@2023-09-01' = {
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
$logDir  = "C:\WindowsAzure\Logs"
$logFile = "$logDir\ConfigureOsState.log"

New-Item -ItemType Directory -Path $logDir -Force | Out-Null

Start-Transcript -Path $logFile -Append

$now = (Get-Date -Format u)
$vmName = $env:COMPUTERNAME

Write-Output "START Configure OS State"
Write-Output "Timestamp (UTC): $now"
Write-Output "Target VM      : $vmName"
Write-Output "Execution User : SYSTEM (Azure Run Command)"

# --- Local admin password reset ---
Write-Output "Password reset initiated."
Write-Output "Target local user : $adminUsername"
Write-Output "Password value    : ****** (masked)"
net user $adminUsername $adminPassword
Write-Output "Password reset result: SUCCESS"

# --- Configure paging file ---
Write-Output "Configuring paging file..."
Set-ItemProperty `
  -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' `
  -Name 'PagingFiles' `
  -Value 'C:\pagefile.sys 4096 8192'

Remove-ItemProperty `
  -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' `
  -Name 'TempPageFile' `
  -ErrorAction SilentlyContinue

Write-Output "Paging file configuration updated."
Write-Output "END Configure OS State"

Stop-Transcript
'''
    }
  }
}
