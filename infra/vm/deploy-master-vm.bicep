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
 * OS Disk (Snapshot → Managed Disk)
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
 * Run Command – Paging file configuration only
 */
resource pagingFileConfig 'Microsoft.Compute/virtualMachines/runCommands@2023-09-01' = {
  name: 'ConfigurePagingFile'
  parent: vm
  location: location
  properties: {
    source: {
      script: '''
$logDir = 'C:\Azure\RunCommand'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$logFile = Join-Path $logDir 'paging-file.log'

Start-Transcript -Path $logFile -Append

Write-Output "START Paging file configuration: $(Get-Date -Format u)"

# OS 安定待ち（最低限）
Start-Sleep -Seconds 60

# 既存ページングファイル設定を上書き
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' `
  /v PagingFiles `
  /t REG_MULTI_SZ `
  /d 'C:\pagefile.sys 4096 8192' `
  /f

# テンポラリページファイル削除
reg delete 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' `
  /v TempPageFile `
  /f

Write-Output 'Paging file updated successfully.'

Stop-Transcript

# 再起動で確実に反映
Restart-Computer -Force
'''
    }
  }
}
