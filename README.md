# AVDReassignLogAnalyticsWorkspace

.SYNOPSIS
    Checks if all AVD VMs in a Ressourcegroup are connected to the right LogAnalyticsWorkspace(LAW) and reassigns them if needed.
.DESCRIPTION
	THis script checks if all VMs in the supplied Ressourcegroup are connected to the correct LAW. If not it reassignes them to the correct LAW. 
	If a machine is not running it is put into maintenance mode, started, reassigned, stoped and then put out of maintenance mode.
	This script is meant to be run in an Azure Runbook. The script will use the AutomationAccount System Identity for Authentication. 
	Therefore the System Identity needs the following RBAC rigths in the Azure tennant:
		- Read on Subscription
		- ..still to be determined
	The following Powershell modules are required:
		- Az.Accounts
		- Az.Compute
		- Az.DesktopVirtualization
		- Az.KeyVault
.PARAMETER Subscription
	The Subscription containig the ressources such as VMs, LAW, KeyVault, Hostpool. 
.PARAMETER VMResourceGroup
	The RessourceGroup that the VMs that need to be checked and reassigned are located in.
.PARAMETER LAWName
	The name of the LogAnalyticsWorkspace the VMs should be connected to.
.PARAMETER WorkspaceID
	The WorkspaceID of the LogAnalyticsWorkspace the VMs should be connected to.
.PARAMETER LAWResourceGroup
	The RessourceGroup containing the LogAnalyticsWorkspace.
.PARAMETER KeyvaultID
	The KeyvaultID where the WorkspaceKey is stored.
.PARAMETER KvWorkspaceKey
	The name of the key in the keyvault that contains the secret workspace key.
.PARAMETER Hostpoolname
	The name of the hostpool that contains the VMs
.PARAMETER HostpoolRessourceGroup
	The RessourceGroup containing the hostpool.
.PARAMETER Extension
	The name of the LAW extension, currently MicrosoftMonitoringAgent.
.NOTES
	- check and revise how VMs that are offline and not part of the hostpool are handeld
	- parameter "Extension" can probaply be removed 
	- maybe reduce parameters with more automatic generation eg. get hostpool from vm
    - check needed Azure RBAC roles and document them
