Import-Module "C:\Program Files\Citrix\Provisioning Services Console\Citrix.PVS.SnapIn.dll"
if (-not (Get-PSSnapin | where {$_.Name -Like "*Citrix*"})) {
    Add-PSSnapin Citrix*
}


Function Export-MachineCatalog {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$True)]
        $MahineCatalog,
        [ValidateSet('DC1','DC2','DC3', 'DC4')]
        $DC,
        [ValidateSet('PVS1','PVS2','PVS3', 'PVS4')]
        $PVS,
        [Switch] $DisasterRecovery

    )

    BEGIN{     

        $logs = Start-LogHighLevelOperation  -AdminAddress $DC -Source "Studio" -StartTime (Get-Date).ToString() -Text "Exporting Machine Catalog `'$MahineCatalog`'"
        Write-Verbose "Creating log in Studio with ID: $($logs.Id)"

        $Location = $MyInvocation.MyCommand.Path -replace $MyInvocation.MyCommand.Name,""
        set-location $Location

    }
    PROCESS{
        $MC = Get-BrokerCatalog -AdminAddress $DC -Name $MahineCatalog | SELECT -Property *
        $Results = @()
        $CatalogPCs = @()

        #foreach ($property in $MC.PSObject.Properties) { $property.Name  }

        if ($DisasterRecovery) {
            if ($MC.Name.StartsWith('XA_FARM1')) {$MC.Name = "XA_BACKUPFARM1" + $mc.Name.Substring(7)}    
        }

        $Properties = @{
            AllocationType = $MC.AllocationType
            AppDnaAnalysisState = $MC.AppDnaAnalysisState
            AssignedCount = $MC.AssignedCount
            AvailableAssignedCount = $MC.AvailableAssignedCount
            AvailableCount = $MC.AvailableCount
            AvailableUnassignedCount = $MC.AvailableUnassignedCount
            Description = $MC.Description
            HypervisorConnectionUid = $MC.HypervisorConnectionUid
            IsRemotePC = $MC.IsRemotePC
            MachinesArePhysical = $MC.MachinesArePhysical
            MetadataMap = $MC.MetadataMap
            MinimumFunctionalLevel = $MC.MinimumFunctionalLevel
            Name = $MC.Name
            PersistUserChanges = $MC.PersistUserChanges
            ProvisioningSchemeId = $MC.ProvisioningSchemeId
            ProvisioningType = $MC.ProvisioningType
            PvsAddress = $MC.PvsAddress
            PvsDomain = $MC.PvsDomain
            RemotePCDesktopGroupPriorities = $MC.RemotePCDesktopGroupPriorities
            RemotePCDesktopGroupUids = $MC.RemotePCDesktopGroupUids
            RemotePCHypervisorConnectionUid = $MC.RemotePCHypervisorConnectionUid
            Scopes = $MC.Scopes
            SessionSupport = $MC.SessionSupport
            TenantId = $MC.TenantId
            UUID = $MC.UUID
            Uid = $MC.Uid
            UnassignedCount = $MC.UnassignedCount
            UsedCount = $MC.UsedCount
            ZoneName = $MC.ZoneName
            ZoneUid = $MC.ZoneUid
        }

        $Results += New-Object PSObject -Property $Properties

        foreach ($pc in (Get-BrokerMachine -CatalogName $MahineCatalog)) { $CatalogPCs += $pc}
    }
    END{
        $FileName = $MahineCatalog + $(Get-Date -Format yyyyMMddTHHmm) + "MC.xml"
        $Results | export-clixml .\$FileName

        $PCsFileName = $MahineCatalog + $(Get-Date -Format yyyyMMddTHHmm) + "PC.xml"
        $CatalogPCs | Export-Clixml .\$PCsFileName
    }
}

Export-MachineCatalog -MahineCatalog "XA_FARM1DELIVERYGROUP" -DC DC1 -PVS PVS1 -DisasterRecovery