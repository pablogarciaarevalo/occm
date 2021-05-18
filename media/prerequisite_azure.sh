#!/bin/bash

#prepare msi name
userMSIName="snapcenter-MSI-"${ConnectorName}

#echo "user msi name is: " $userMSIName
echo "user msi name is: " $userMSIName

#set az account
az account set --subscription ${SubscriptionID}

#Create user managed identity under the given OCCM service connector's resource group
userMSIPrincipleID=$(az identity create -g $ResourceGroup -n $userMSIName --query 'principalId' -o tsv)

echo "user managed identity created, PrincipleID: " ${userMSIPrincipleID}

#prepare managed cluster role name
strhypen="-"
ManagedClusterRoleName="snapcenter-manged-cluster-"${ResourceGroup}${strhypen}${ConnectorName}

#prepare occm rg scope
rgScope="/subscriptions/$SubscriptionID/resourceGroups/"${ResourceGroup}

echo $rgScope

#create custom role snapcenter managed cluster at rg scope
ManagedClusterRoleDefID=$(az role definition create --role-definition '{
  "Name":"'$ManagedClusterRoleName'",
  "IsCustom": true,
  "Description": "Can create/update/delete aks cluster",
  "Actions": [
   "Microsoft.Resources/subscriptions/resourceGroups/read",
   "Microsoft.ContainerService/managedClusters/write",
   "Microsoft.ContainerService/managedClusters/read",
   "Microsoft.ManagedIdentity/userAssignedIdentities/assign/action",
   "Microsoft.ManagedIdentity/userAssignedIdentities/read",
   "Microsoft.ContainerService/managedClusters/delete",
   "Microsoft.Compute/virtualMachines/read",
   "Microsoft.Network/networkInterfaces/read",
   "Microsoft.ContainerService/managedClusters/listClusterUserCredential/action"
  ],
  "NotActions": [

  ],
  "AssignableScopes": [
    "'$rgScope'"
  ]
}' --query 'id' -o tsv)

echo "custom role '$ManagedClusterRoleName' created, RoleDefinationID:" $ManagedClusterRoleDefID

#prepare managed cluster role name
NetworkManagementRoleName="snapcenter-network-management-"${ResourceGroup}${strhypen}${ConnectorName}


#Get occm connector's subnet scope
nic=$(az vm show -n $ConnectorName -g $ResourceGroup --query 'networkProfile.networkInterfaces[0].id' -o tsv)

echo "NIC:"$nic

subnetScope=$(az vm nic show -g $ResourceGroup --vm-name $ConnectorName --nic $nic --query 'ipConfigurations[0].subnet.id' -o tsv)

#get network subscriptionID
networkSubscriptionID=($(cut -d'/' -f3 <<<$subnetScope))
echo "networkSubscriptionID: " $networkSubscriptionID

#get network resourcegroup
networkResourceGroup=($(cut -d'/' -f5 <<<$subnetScope))
echo "networkResourceGroup: " $networkResourceGroup

#get network vnet name
virtualNetworkName=($(cut -d'/' -f9 <<<$subnetScope))
echo "virtualNetworkName: " $virtualNetworkName

#prepare vnet scope
vnetScope="/subscriptions/$networkSubscriptionID/resourceGroups/$networkResourceGroup/providers/Microsoft.Network/virtualNetworks/$virtualNetworkName"
echo "vnetScope: " $vnetScope

#create snapcenter network management custom role at occm vnet scope
az role definition create --role-definition '{
  "Name": "'$NetworkManagementRoleName'",
  "IsCustom": true,
  "Description": "Can create/update/delete aks cluster",
  "Actions": [
   "Microsoft.Network/virtualNetworks/subnets/read",
   "Microsoft.Authorization/roleAssignments/read",
   "Microsoft.Network/virtualNetworks/subnets/join/action",
   "Microsoft.Network/virtualNetworks/read"
  ],
  "NotActions": [
  ],
  "AssignableScopes": [
    "'$vnetScope'"
  ]
}'

#sleep for few seconds, because sometimes user msi wont be created, adding sleep for 45 seconds
echo "adding sleep for 45 seconds, to ensure MSI is already created before role assignment, Despite this if role assignment fails then simply re-execute this script"
sleep 45

#Assign custom role to user msi
az role assignment create --assignee $userMSIPrincipleID --role $ManagedClusterRoleName --resource-group $ResourceGroup

#sleep for few seconds, because azure sometimes takes time to reflect the permissions
echo "adding sleep for another 45 seconds, to make sure permissions are reflected"
sleep 45

#Assign Network Contributor role to user msi
az role assignment create --assignee $userMSIPrincipleID --role $NetworkManagementRoleName --scope $vnetScope

#Assign user msi to occm connector
az vm identity assign -g $ResourceGroup -n $ConnectorName --identities $userMSIName

bold=$(tput bold)
normal=$(tput sgr0)

echo "User assigned managed identity ${bold}'$userMSIName'${normal} successfully created and assigned to connector."
