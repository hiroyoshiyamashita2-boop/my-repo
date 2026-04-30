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
resource fixOsStateExtension 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = {
  name: 'FixOsStateWithLogging'
  parent: vm
  location: location
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true

    settings: {
      commandToExecute: '''
powershell -ExecutionPolicy Bypass -Command "

$logDir = 'C:\\Azure\\CustomScript'
$logFile = '${logFilePath}'

New-Item -ItemType Directory -Path $logDir -Force | Out-Null
Start-Transcript -Path $logFile -Append

Write-Output '=== Fix OS State Script START ==='
Write-Output \"Timestamp: $(Get-Date -Format u)\"

Start-Sleep -Seconds 30

Write-Output 'Waiting for Azure VM heartbeat service...'
while ((Get-Service vmicheartbeat).Status -ne 'Running') {
  Start-Sleep -Seconds 5
}
Write-Output 'OS is ready.'

# --- パスワードリセット ---
net user ${adminUsername} $env:ADMIN_PASSWORD
Write-Output 'Password reset completed.'

# --- ページングファイル設定 ---
reg add 'HKLM\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Memory Management' `
 /v PagingFiles `
 /t REG_MULTI_SZ `
 /d 'C:\\pagefile.sys 4096 8192' `
 /f

reg delete 'HKLM\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Memory Management' `
 /v TempPageFile `
 /f

Write-Output 'Paging file configuration updated.'
Write-Output '=== Fix OS State Script END ==='

Stop-Transcript
"
'''
    }

    protectedSettings: {
      ADMIN_PASSWORD: adminPassword
    }
  }
}
