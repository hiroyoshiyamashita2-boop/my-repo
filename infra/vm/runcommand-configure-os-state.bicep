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

resource preReboot 'Microsoft.Compute/virtualMachines/runCommands@2023-09-01' = {
  name: 'ConfigureOsState-PreReboot'
  parent: vm
  location: location
  properties: {
    parameters: [
      { name: 'adminUsername'; value: adminUsername }
      { name: 'adminPassword'; value: adminPassword }
    ]
    source: {
      script: '''
param(
  [string]$adminUsername,
  [string]$adminPassword
)

$logDir  = "C:\WindowsAzure\Logs"
$logFile = "$logDir\PreReboot.log"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
Start-Transcript -Path $logFile -Append

net user $adminUsername $adminPassword

wmic computersystem where name="%COMPUTERNAME%" set AutomaticManagedPagefile=False | Out-Null
Set-ItemProperty `
  -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' `
  -Name 'PagingFiles' `
  -Value @()

if (-not (Get-Module -ListAvailable PSWindowsUpdate)) {
  Install-PackageProvider NuGet -Force
  Install-Module PSWindowsUpdate -Force -Confirm:$false
}

Import-Module PSWindowsUpdate
Install-WindowsUpdate -AcceptAll -IgnoreReboot -Verbose

Stop-Transcript
'''
    }
  }
}

resource rebootVm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: vmName
  location: location
  properties: {
    restart: true
  }
  dependsOn: [
    preReboot
  ]
}
