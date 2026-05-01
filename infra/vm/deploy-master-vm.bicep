@description('Azure region')
param location string

@description('Target virtual machine name')
param vmName string

@description('Local administrator username (must already exist)')
param adminUsername string = 'avdlocaladmin'

@secure()
@description('New password for local administrator user')
param adminPassword string

/*
 * Existing Virtual Machine
 */
resource vm 'Microsoft.Compute/virtualMachines@2023-09-01' existing = {
  name: vmName
}

/*
 * Run Command
 * - Reset local admin password
 * - Configure paging file
 * - Save logs to C:\WindowsAzure\Logs
 */
resource configureOsStateRunCommand 'Microsoft.Compute/virtualMachines/runCommands@2023-09-01' = {
  name: 'ConfigureOsState'
  parent: vm
  location: location
  properties: {
    source: {
      script: '''
$logDir  = "C:\WindowsAzure\Logs"
$logFile = "$logDir\ConfigureOsState.log"

# Ensure log directory exists
New-Item -ItemType Directory -Path $logDir -Force | Out-Null

Start-Transcript -Path $logFile -Append

Write-Output "START Configure OS State: $(Get-Date -Format u)"

# --- Local admin password reset ---
Write-Output "Resetting local administrator password..."
net user ${adminUsername} "${adminPassword}"
Write-Output "Local administrator password reset completed."

# --- Configure paging file ---
Write-Output "Configuring paging file..."
Set-ItemProperty `
  -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' `
  -Name 'PagingFiles' `
  -Value 'C:\pagefile.sys 4096 8192'

# Remove TempPageFile if exists
Remove-ItemProperty `
  -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' `
  -Name 'TempPageFile' `
  -ErrorAction SilentlyContinue

Write-Output "Paging file configuration updated."
Write-Output "END Configure OS State: $(Get-Date -Format u)"

Stop-Transcript
'''
    }
  }
}
