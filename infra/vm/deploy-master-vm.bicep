@description('Azure region')
param location string

@description('Snapshot name to create OS disk from')
param snapshotName string

@description('Virtual Machine name')
param vmName string

@description('Deployment date (YYYYMMDD)')
param deployDate string

@description('Virtual Machine size')
param vmSize string = 'Standard_D2s_v5'

@description('Existing virtual network name')
param vnetName string = 'P906VNJWPB01'

@description('Existing subnet name')
param subnetName string = 'AVD-MNG-JW'

@description('Existing local admin username (must already exist in snapshot)')
param adminUsername string = 'avdlocaladmin'

@secure()
@description('New password for existing local admin user')
param adminPassword string

var osDiskName = '${vmName}-OsDisk01-${deployDate}'
var logFilePath = 'C:\\Azure\\CustomScript\\fix-os-state.log'

/*
 * Existing Virtual Network
 */
resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' existing = {
  name: vnetName
}

/*
 * Existing Subnet
 */
resource subnet 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' existing = {
  parent: vnet
  name: subnetName
}

/*
 * Existing Snapshot
 */
resource snapshot 'Microsoft.Compute/snapshots@2023-10-02' existing = {
  name: snapshotName
}

/*
 * OS Disk (Snapshot -> Managed Disk)
 */
resource osDisk 'Microsoft.Compute/disks@2023-10-02' = {
  name: osDiskName
  location: location
  sku: {
    name: 'StandardSSD_LRS'
  }
  properties: {
    creationData: {
      createOption: 'Copy'
      sourceResourceId: snapshot.id
    }
    osType: 'Windows'
  }
}

/*
 * Network Interface
 */
resource nic 'Microsoft.Network/networkInterfaces@2023-11-01' = {
  name: '${vmName}-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: subnet.id
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}

/*
 * Virtual Machine (Trusted Launch)
 */
resource vm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    securityProfile: {
      securityType: 'TrustedLaunch'
      uefiSettings: {
        secureBootEnabled: true
        vTpmEnabled: true
      }
    }
    storageProfile: {
      osDisk: {
        name: osDiskName
        createOption: 'Attach'
        managedDisk: {
          id: osDisk.id
        }
        osType: 'Windows'
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
  }
}

/*
 * Custom Script Extension
 * - パスワードリセット
 * - ページングファイル調整
 * - 実行ログを VM 内に永続保存
 */

resource runCmd 'Microsoft.Compute/virtualMachines/runCommands@2023-09-01' = {
  name: 'FixOsState'
  parent: vm
  location: location
  properties: {
    source: {
      script: '''
$logDir = "C:\Azure\RunCommand"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$log = "$logDir\fix-os.log"

"START $(Get-Date)" | Out-File $log -Append

net user avdlocaladmin 'NewPasswordHere'
"Password updated" | Out-File $log -Append

reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" `
 /v PagingFiles `
 /t REG_MULTI_SZ `
 /d "C:\pagefile.sys 4096 8192" `
 /f

"Paging file updated" | Out-File $log -Append
"END $(Get-Date)" | Out-File $log -Append
'''
    }
  }
}

