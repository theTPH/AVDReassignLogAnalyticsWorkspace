<#
.SYNOPSIS
    Checks if all AVD VMs in a Ressourcegroup are connected to the right LogAnalyticsWorkspace(LAW) and reassigns them if needed.
.DESCRIPTION
	THis script checks if all VMs in the supplied Ressourcegroup are connected to the correct LAW. If not it reassignes them to the correct LAW. 
	If a machine is not running it is put into maintenance mode, started, reassigned, stoped and then put out of maintenance mode.
	This script is meant to be run in an Azure Runbook. The script will use the AutomationAccount System Identity for Authentication. 
	Therefore the System Identity needs the following RBAC rigths in the Azure tennant:
		- Read on KeyVault
		- Virtual Machine Contributor on VMRessourceGroup
		- Log Analytics Contributor on LogAnalyticsWorkspace
		- Desktop Virtualization Contributor on Hostpool
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
#>

Param (
	[Parameter (Mandatory = $true)]
	[String] $Subscription,
	[Parameter (Mandatory = $true)]
	[String] $VMResourceGroup,
	[Parameter (Mandatory = $true)]
	[String] $LAWName,
	[Parameter (Mandatory = $true)]
	[String] $WorkspaceID,
	[Parameter (Mandatory = $true)]
	[String] $LAWResourceGroup,
	[Parameter (Mandatory = $true)]
	[String] $KeyvaultID,
	[Parameter (Mandatory = $true)]
	[String] $KvWorkspaceKey,
	[Parameter (Mandatory = $true)]
	[String] $Hostpoolname,
	[Parameter (Mandatory = $true)]
	[String] $HostpoolRessourceGroup,
	[Parameter (Mandatory = $false)]
	[String] $Extension = "MicrosoftMonitoringAgent"
)

function Reassign-VM
{
    [CmdletBinding()]
   	Param(
       	[Parameter(Mandatory)]
        [string]$VMName,
       
   	    [Parameter(Mandatory)]
       	[string]$ResourceGroupName,
       
        [Parameter(Mandatory)]
   	    [string]$Location,

        [Parameter(Mandatory)]
   	    [string]$Extension,

        [Parameter(Mandatory)]
   	    [string]$WorkspaceID,

        [Parameter(Mandatory)]
   	    [string]$WorkspaceKey
   	)

    Write-Output("Removing " + $VMName + " from old workspace")
    Remove-AzVMExtension -ResourceGroupName $ResourceGroupName -VMName $VMName -Name $Extension  -Force

    Write-Output("Adding " + $VMName + " to new workspace...")
    Set-AzVMExtension -Name $Extension `
        -ResourceGroupName $ResourceGroupName `
        -VMName $VMName `
        -Publisher "Microsoft.EnterpriseCloud.Monitoring" `
        -ExtensionType $Extension `
        -TypeHandlerVersion "1.0" `
        -Location $Location `
        -SettingString "{'workspaceId': '$WorkspaceID'}" `
        -ProtectedSettingString "{'workspaceKey': '$WorkspaceKey'}"
}

function Check-LAWAssignment
{
    [CmdletBinding()]
   	Param(
       	[Parameter(Mandatory)]
        [string]$LAWResourceGroup,
       
   	    [Parameter(Mandatory)]
       	[string]$LAWName,
       
        [Parameter(Mandatory)]
   	    [string]$ExtensionName,

        [Parameter(Mandatory)]
   	    [string]$VMName,

        [Parameter(Mandatory)]
   	    [string]$VMResourceGroup
   	)
    $LAWorkspace = Get-AzOperationalInsightsWorkspace -ResourceGroupName $LAWResourceGroup -Name $LAWName
    $VMExtensionObject = Get-AzVMExtension -ResourceGroupName $VMResourceGroup -VMName $VMName -Name $ExtensionName -ErrorAction SilentlyContinue
    $IsConnected = $false
    if($VMExtensionObject)
    { 
        $WorkspaceID = ($VMExtensionObject.PublicSettings | ConvertFrom-Json).workspaceId

        if($LAWorkspace.CustomerId.Guid -eq $WorkspaceID)
        { 
            $IsConnected = $true
        }
    }

    return $IsConnected
}

Write-Output ("Running script on: " + $env:computername)
#Connect to Azure with the identity of the automation account
try {
    Write-Output ("Connecting to Azure Account...")
    Connect-AzAccount `
    -Identity `
    -SubscriptionId $Subscription `
    -ErrorAction Stop| Out-Null 
}
catch {
    $ErrorMessage = $PSItem.Exception.message
    Write-Error ("Could not connect to Azure Account: "+$ErrorMessage)
    exit(1)
    Break
}

#Get workspace key from keyvault
try {
    Write-Output ("Collecting workspace key...")
	$WorkspaceKey = Get-AzKeyVaultSecret -ResourceId $KeyvaultID -Name $KvWorkspaceKey -AsPlainText 
}
catch {
    $ErrorMessage = $PSItem.Exception.message
    Write-Error ("Could not collect workspace key: "+$ErrorMessage)
    exit(1)
    Break
}
Write-Output("Collected worksace key")

Get-AzVM | Where-Object{$_.ResourceGroupName -eq $VMResourceGroup} | ForEach-Object {
    $provisioningState = (Get-AzVM -ResourceGroupName $_.ResourceGroupName  -Name $_.Name -Status).Statuses[1].Code #Statuscode if the machine is currently running
    $IsConnected = Check-LAWAssignment -LAWResourceGroup $LAWResourceGroup -LAWName $LAWName -ExtensionName $Extension -VMName $_.Name -VMResourceGroup $_.ResourceGroupName
    if($IsConnected -eq $false)
    {
        Write-Output("VM $($_.Name) is not connected to the correct LogAnalyticsWorkspace")
        if ($provisioningState -eq "PowerState/running")
        {
			#If the VM is running it gets reassigned to the new LAW
            Write-Output("VM " + $_.Name + " is running")
            Write-Output("Reassigning VM $($_.Name)")
            Reassign-VM -VMName $_.Name -ResourceGroupName $_.ResourceGroupName  -Location $_.Location -Extension $Extension -WorkspaceID $WorkspaceID -WorkspaceKey $WorkspaceKey

        }
        elseif ($provisioningState -eq "PowerState/deallocated")
        {
			#If the VM is not running it is-
            Write-Output("VM " + $_.Name + " is deallocated, putting it into drain mode")
            $VMFullName = $_.Name + ".aaddsrtlgroup.com"
            Update-AzWvdSessionHost -HostPoolName $Hostpoolname -ResourceGroupName $HostpoolRessourceGroup -Name $VMFullName -AllowNewSession:$false # -put into maintenance mode
            Write-Output("Starting VM $($_.Name)")
            Start-AzVM -Name $_.Name -ResourceGroupName $_.ResourceGroupName # -started
            $provisioningState = (Get-AzVM -ResourceGroupName $_.ResourceGroupName  -Name $_.Name -Status).Statuses[1].Code
            Write-Output("Reassigning VM $($_.Name)")
            Reassign-VM -VMName $_.Name -ResourceGroupName $_.ResourceGroupName  -Location $_.Location -Extension $Extension -WorkspaceID $WorkspaceID -WorkspaceKey $WorkspaceKey # -reassigned
            Write-Output("Stopping VM $($_.Name) and oull it out of drain mode")
            Stop-AzVM -Name $_.Name -ResourceGroupName $_.ResourceGroupName -Force # -stopped
            Update-AzWvdSessionHost -HostPoolName $Hostpoolname -ResourceGroupName $HostpoolRessourceGroup -Name $VMFullName -AllowNewSession:$true # -put out of maintenance mode
        }
        else
        {
			#All other provisioning states like "deallocating" are currently not handeld in this script
           Write-Warning("VM " + $_.Name + " is in unknown provisioning state " + $provisioningState)
        }
    }else{
		#No action is taken if the VM is already connected to the correct Workspace
        Write-Output("VM $($_.Name) is allready connected to the correct LogAnalyticsWorkspace")
    }
 }
