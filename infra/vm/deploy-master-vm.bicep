@description('Azure region')
param location string

@description('Snapshot name to create OS disk from')
param snapshotName string

@description('Virtual Machine name')
param vmName string

@description('Deployment date (YYYYMMDD)')
param deployDate string

@description('Admin username for Master VM')
param adminUsername string = 'avdlocaladmin'

@secure()
@description('Admin password for Master VM (per-VM)')
param adminPassword string

@description('Virtual Machine size')
param vmSize string = 'Standard_D2s_v5'

@description('Existing virtual network name')
param vnetName string = 'P906VNJWPB01'

@description('Existing subnet name')
param subnetName string = 'AVD-MNG-JW'

var osDiskName = '${vmName}-OsDisk01-${deployDate}'

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
 * OS Disk
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
 * NIC
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
 * VM (Trusted Launch)
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
        { id: nic.id }
      ]
    }
  }
}

//
// ① 管理者パスワード再設定
//
resource resetAdminPassword 'Microsoft.Compute/virtualMachines/runCommands@2023-09-01' = {
  name: 'ResetAdmin'
  parent: vm
  location: location
  properties: {
    source: {
      script: $'''
net user ${adminUsername} ${adminPassword}
net localgroup Administrators ${adminUsername} /add
'''
    }
  }
}

//
// ② Windows Update
//
resource windowsUpdate 'Microsoft.Compute/virtualMachines/runCommands@2023-09-01' = {
  name: 'WindowsUpdate'
  parent: vm
  location: location
  dependsOn: [ resetAdminPassword ]
  properties: {
    source: {
      script: $'''
Install-PackageProvider -Name NuGet -Force
Install-Module PSWindowsUpdate -Force
Import-Module PSWindowsUpdate
Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -AutoReboot
'''
    }
  }
}

//
// ③ ページングファイル修復（レジストリ直書き）★最重要
//
resource fixPagingFileRegistry 'Microsoft.Compute/virtualMachines/runCommands@2023-09-01' = {
  name: 'FixPagingRegistry'
  parent: vm
  location: location
  dependsOn: [ windowsUpdate ]
  properties: {
    source: {
      script: $'''
reg add "HKLM\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Memory Management" ^
 /v PagingFiles ^
 /t REG_MULTI_SZ ^
 /d "C:\\pagefile.sys 4096 8192" ^
 /f

reg delete "HKLM\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Memory Management" ^
 /v TempPageFile ^
 /f
'''
    }
  }
}

//
// ④ 再起動（1回のみ）
/// 
resource restartVm 'Microsoft.Compute/virtualMachines/runCommands@2023-09-01' = {
  name: 'RestartAfterFix'
  parent: vm
  location: location
  dependsOn: [ fixPagingFileRegistry ]
  properties: {
    source: {
      script: $'''
Restart-Computer -Force
'''
    }
  }
}
