Import-Module "C:\Program Files\Citrix\Provisioning Services Console\Citrix.PVS.SnapIn.dll"
if (-not (Get-PSSnapin | where {$_.Name -Like "*Citrix*"})) {
    Add-PSSnapin Citrix*
}
 
Function Export-Application {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        $DeliveryGroup,
        [ValidateSet('DC1','DC2','DC3', 'DC')]
        $DC,
        [Switch]
        $DisasterRecovery
    )
    BEGIN{      
        $logs = Start-LogHighLevelOperation  -AdminAddress $DC -Source "Studio" -StartTime (Get-Date).ToString() -Text "Exporting applications for Delivery Group `'$DeliveryGroup`'"
        Write-Verbose "Creating log in Studio with ID: $($logs.Id)"

        $Location = $MyInvocation.MyCommand.Path -replace $MyInvocation.MyCommand.Name,""
        set-location $Location

        $DG = Get-BrokerDesktopGroup -AdminAddress $DC -Name $DeliveryGroup

    }
    PROCESS{
        $Apps = Get-BrokerApplication -AssociatedDesktopGroupUid $DG.Uid -MaxRecordCount 2147483647
        $Results = @()

        foreach($App in $Apps) {

            if ($DisasterRecovery) {
                if ($App.AdminFolderName.StartsWith('XA_FARM1')) {$App.AdminFolderName = "XA_BACKUPFARM1" + $App.AdminFolderName.Substring(7)}    
            }
	
	        $Properties = @{
		
	        AdminFolderName = $App.AdminFolderName
	        AdminFolderUid  = $App.AdminFolderUid
	        AllAssociatedDesktopGroupUids = $App.AllAssociatedDesktopGroupUids
	        AllAssociatedDesktopGroupUUIDs = $App.AllAssociatedDesktopGroupUUIDs
	        ApplicationName = $App.ApplicationName
	        ApplicationType = $App.ApplicationType
	        AssociatedApplicationGroupUids = $App.AssociatedApplicationGroupUids
	        AssociatedApplicationGroupUUIDs = $App.AssociatedApplicationGroupUUIDs
	        AssociatedDesktopGroupPriorities = $App.AssociatedDesktopGroupPriorities
	        AssociatedDesktopGroupUids = $App.AssociatedDesktopGroupUids
	        AssociatedDesktopGroupUUIDs = $App.AssociatedDesktopGroupUUIDs
	        AssociatedUserFullNames = $App.AssociatedUserFullNames
	        AssociatedUserNames = $App.AssociatedUserNames
	        AssociatedUserUPNs = $App.AssociatedUserUPNs
	        BrowserName = $App.BrowserName
	        ClientFolder = $App.ClientFolder
	        CommandLineArguments = $App.CommandLineArguments
	        CommandLineExecutable = $App.CommandLineExecutable
	        ConfigurationSlotUids = $App.ConfigurationSlotUids
	        CpuPriorityLevel = $App.CpuPriorityLevel
	        Description = $App.Description
	        Enabled = $App.Enabled
	        HomeZoneName = $App.HomeZoneName
	        HomeZoneOnly = $App.HomeZoneOnly
	        HomeZoneUid = $App.HomeZoneUid
	        IconFromClient  = $App.IconFromClient
	        EncodedIconData = (Get-Brokericon -Uid $App.IconUid).EncodedIconData # Grabs Icon Image
	        IconUid = $App.IconUid
	        IgnoreUserHomeZone = $App.IgnoreUserHomeZone
	        MachineConfigurationNames = $App.MachineConfigurationNames
	        MachineConfigurationUids = $App.MachineConfigurationUids
	        MaxPerUserInstances = $App.MaxPerUserInstances
	        MaxTotalInstances = $App.MaxTotalInstances
	        MetadataKeys = $App.MetadataKeys
	        MetadataMap = $App.MetadataMap
	        Name = $App.Name
	        PublishedName = $App.PublishedName
	        SecureCmdLineArgumentsEnabled = $App.SecureCmdLineArgumentsEnabled
	        ShortcutAddedToDesktop = $App.ShortcutAddedToDesktop
	        ShortcutAddedToStartMenu = $App.ShortcutAddedToStartMenu
	        StartMenuFolder = $App.StartMenuFolder
	        Tags = $App.Tags
	        Uid = $App.Uid
	        UserFilterEnabled = $App.UserFilterEnabled
	        UUID = $App.UUID
	        Visible = $App.Visible
	        WaitForPrinterCreation = $App.WaitForPrinterCreation
	        WorkingDirectory = $App.WorkingDirectory

        }

        # Stores each Application setting for export

        $Results += New-Object psobject -Property $Properties
    }
    }

    END{
        $FileName = $DeliveryGroup + $(Get-Date -Format yyyyMMddTHHmm) + "AP.xml"
        $Results | export-clixml .\$FileName
    }
}

Export-Application -DeliveryGroup XA_PPHXUEMCTX -DC pphxctxdc1 -DisasterRecovery