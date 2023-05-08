// Run with `az deployment group create --resource-group resource-group-name --name MainDeployment --template-file main.bicep --parameters @local.parameters.json`

@description('The location for the Azure resources - typically westus3.')
param location string = resourceGroup().location

@description('The environment name - typically dev, test, or prod.')
param environment string

@description('The VM sku size - can be found using `az vm list-skus --location westus3 --query "[].name" --output tsv`')
param vmSize string = 'Standard_D4as_v5'

param adminUsername string

@secure()
param adminPassword string

@description('The Windows version for the VM. This will pick a fully patched image of this given Windows version.')
@allowed([
  '2019-datacenter-core-g2'
  '2019-datacenter-core-smalldisk-g2'
  '2019-datacenter-core-with-containers-g2'
  '2019-datacenter-core-with-containers-smalldisk-g2'
  '2019-datacenter-gensecond'
  '2019-datacenter-smalldisk-g2'
  '2019-datacenter-with-containers-g2'
  '2019-datacenter-with-containers-smalldisk-g2'
  '2019-datacenter-zhcn-g2'
  '2022-datacenter-azure-edition'
  '2022-datacenter-azure-edition-core'
  '2022-datacenter-azure-edition-core-smalldisk'
  '2022-datacenter-azure-edition-smalldisk'
  '2022-datacenter-core-g2'
  '2022-datacenter-core-smalldisk-g2'
  '2022-datacenter-g2'
  '2022-datacenter-smalldisk-g2'
])
param osVersion string = '2022-datacenter-azure-edition'

param updateTag string = utcNow()

resource vmManagedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: 'umi-${environment}-${location}'
  location: location
}

resource publicIpAddress 'Microsoft.Network/publicIPAddresses@2022-09-01' = {
  name: 'pip-${environment}-${location}'
  location: location
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource bastionHost 'Microsoft.Network/bastionHosts@2022-09-01' = {
  name: 'bh-${environment}-${location}'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    scaleUnits: 5
    ipConfigurations: [
      {
        name: 'ipconfiguration'
        properties: {
          subnet: {
            id: virtualNetwork.properties.subnets[0].id
          }
          publicIPAddress: { 
            id: publicIpAddress.id
          }
        }
      }
    ]
  }
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2022-05-01' = {
  name: 'vnet-${environment}-${location}'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [ '10.16.0.0/25' ]
    }
    // Because https://github.com/Azure/bicep/issues/4653
    subnets: [
      {
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: '10.16.0.0/27'
        }
      }
      {
        name: 'vmsubnet'
        properties: {
          addressPrefix: '10.16.0.32/27'
        }
      }
    ]
  }
}

resource networkInterface 'Microsoft.Network/networkInterfaces@2022-05-01' = {
  name: 'nic-${environment}-${location}'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: virtualNetwork.properties.subnets[1].id
          }
        }
      }
    ]
  }
}

resource virtualMachine 'Microsoft.Compute/virtualMachines@2022-03-01' = {
  name: 'vm-${environment}-${location}'
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${vmManagedIdentity.id}': {}
    }
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: 'build'
      adminUsername: adminUsername
      adminPassword: adminPassword
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: osVersion
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
        deleteOption: 'Delete'
      }
      dataDisks: [
        {
          lun: 0
          createOption: 'Empty'
          caching: 'ReadWrite'
          name: 'vm-${environment}-${location}-datadisk'
          diskSizeGB: 2048
          deleteOption: 'Delete'
        }
      ]
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: networkInterface.id
          properties: {
            deleteOption: 'Delete'
          }
        }
      ]
    }
  }
}

resource installerScriptExtension 'Microsoft.Compute/virtualMachines/extensions@2022-11-01' = {
  parent: virtualMachine
  name: 'installerScript'
  location: location
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true
    settings: {
      commandToExecute: 'powershell.exe -ExecutionPolicy Unrestricted -Command "Invoke-Expression -Command ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String(\'${loadFileAsBase64('runOnAgent.ps1')}\')))"'
    }
    protectedSettings: {
      managedIdentity: {
        clientId: vmManagedIdentity.properties.clientId
      }
    }
    forceUpdateTag: updateTag
  }
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2022-09-01' = {
  name: 'juswenteststorage'
  location: location
  kind: 'BlobStorage'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    accessTier: 'Cool'
    allowSharedKeyAccess: false
    networkAcls: {
      defaultAction: 'Deny'
    }
  }
}

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.blob.${az.environment().suffixes.storage}'
  location: 'global'
  dependsOn: [
    virtualNetwork
  ]
}

resource privateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZone
  name: 'juswen-dns-zone-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetwork.id
    }
  }
}

resource dnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2022-07-01' = {
  parent: privateEndpoint
  name: 'juswen-dns-zone-group'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'vm-storage'
        properties: {
          privateDnsZoneId: privateDnsZone.id
        }
      }
    ]
  }
}

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2022-11-01' = {
  name: 'juswen-private-endpoint'
  location: location
  properties: {
    subnet: virtualNetwork.properties.subnets[1]
    privateLinkServiceConnections: [
      {
        name: 'vm-storage'
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds: [
            'blob'
          ]
        }
      }
    ]
  }
}
