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
 * OS Disk (Snapshot -> Managed Disk)
 * - Snapshot 作成時点のユーザー／パスワードを完全保持
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
 * - OS ディスクは Attach
 * - osProfile は intentionally 未定義（Snapshot 状態を維持）
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
 * - OS 起動安定化待機
 * - ページングファイル調整のみ
 * - ユーザー／パスワードは一切変更しない
 */
resource fixOsStateExtension 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = {
  name: 'FixOsStateAlways'
  parent: vm
  location: location
  dependsOn: [
    vm
    nic
    osDisk
  ]
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true

    settings: {
      commandToExecute: '''
powershell -ExecutionPolicy Bypass -Command "

# --- 初期待機（VM Agent / OS 安定化） ---
Start-Sleep -Seconds 30

# --- OS 完全起動待ち ---
Write-Output 'Waiting for Azure VM heartbeat service...'
while ((Get-Service vmicheartbeat).Status -ne 'Running') {
  Start-Sleep -Seconds 5
}
Write-Output 'OS is ready.'

# --- ページングファイル調整のみ ---
reg add 'HKLM\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Memory Management' `
 /v PagingFiles `
 /t REG_MULTI_SZ `
 /d 'C:\\pagefile.sys 4096 8192' `
 /f

reg delete 'HKLM\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Memory Management' `
 /v TempPageFile `
 /f

Write-Output 'OS state fixed. Existing users and passwords preserved.'
"
'''
    }
  }
}
