@description('Azure region')
param location string

@description('Snapshot name to create OS disk from')
param snapshotName string

@description('Virtual Machine name')
param vmName string

@description('Deployment date (YYYYMMDD)')
param deployDate string

@description('Local admin username')
param adminUsername string = 'avdlocaladmin'

@secure()
@description('Local admin password')
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

//
//  OS 起動後前提・堅牢な Custom Script Extension
//  - dependsOn 明示（vm / nic / osDisk）
//  - 初期待機 + Windows サービス稼働待ち
//  - ローカル管理者作成／更新
//  - ページングファイル レジストリ直接修正
//
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
      commandToExecute: $'''
powershell -ExecutionPolicy Bypass -Command "

# --- 初期待機（VM Agent / OS 安定化） ---
Start-Sleep -Seconds 30

# --- OS 完全起動待ち（Azure VM Heartbeat サービス） ---
Write-Output 'Waiting for Azure VM heartbeat service...'
while ((Get-Service vmicheartbeat).Status -ne 'Running') {
  Start-Sleep -Seconds 5
}
Write-Output 'OS is ready.'

# --- ローカル管理者作成／再設定 ---
$pwd = $env:ADMIN_PASSWORD

if (-not (Get-LocalUser -Name '${adminUsername}' -ErrorAction SilentlyContinue)) {
  net user ${adminUsername} $pwd /add
} else {
  net user ${adminUsername} $pwd
}
net localgroup Administrators ${adminUsername} /add

# --- ページングファイル レジストリ完全修正 ---
reg add 'HKLM\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Memory Management' `
 /v PagingFiles `
 /t REG_MULTI_SZ `
 /d 'C:\\pagefile.sys 4096 8192' `
 /f

reg delete 'HKLM\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Memory Management' `
 /v TempPageFile `
 /f

Write-Output 'OS state (user and paging file) fixed successfully.'
"
'''
    }

    protectedSettings: {
      ADMIN_PASSWORD: adminPassword
    }
  }
}
