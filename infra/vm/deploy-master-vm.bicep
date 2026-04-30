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
 * Existing Snapshot (Gen2 / Trusted Launch 前提)
 */
resource snapshot 'Microsoft.Compute/snapshots@2023-10-02' existing = {
  name: snapshotName
}

/*
 * OS Disk (Standard SSD LRS)
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

//
// ① 管理者パスワード再設定（ログイン安定化）
//
resource resetAdminPassword 'Microsoft.Compute/virtualMachines/runCommands@2023-09-01' = {
  name: 'ResetMasterAdminPassword'
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
  name: 'RunWindowsUpdate'
  parent: vm
  location: location
  dependsOn: [
    resetAdminPassword
  ]
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
// ③ ページングファイルを C:\ に固定（決定打）
//
resource fixPagingFileFinal 'Microsoft.Compute/virtualMachines/runCommands@2023-09-01' = {
  name: 'FixPagingFileFinal'
  parent: vm
  location: location
  dependsOn: [
    windowsUpdate
  ]
  properties: {
    source: {
      script: $'''
# 既存の pagefile 定義をすべて削除
wmic pagefileset delete || exit /b 0

# 自動管理を完全に OFF
wmic computersystem where name="%computername%" set AutomaticManagedPagefile=False

# C:\\ に pagefile を明示作成（安定構成）
wmic pagefileset create name="C:\\pagefile.sys"
wmic pagefileset where name="C:\\pagefile.sys" set InitialSize=4096,MaximumSize=8192
'''
    }
  }
}

//
// ④ 再起動（1回だけ）
//
resource restartVm 'Microsoft.Compute/virtualMachines/runCommands@2023-09-01' = {
  name: 'RestartAfterPagingFix'
  parent: vm
  location: location
  dependsOn: [
    fixPagingFileFinal
  ]
  properties: {
    source: {
      script: $'''
Restart-Computer -Force
'''
    }
  }
}
