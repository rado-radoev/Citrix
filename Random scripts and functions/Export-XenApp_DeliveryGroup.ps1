Import-Module "C:\Program Files\Citrix\Provisioning Services Console\Citrix.PVS.SnapIn.dll"
if (-not (Get-PSSnapin | where {$_.Name -Like "*Citrix*"})) {
    Add-PSSnapin Citrix*
}

Function Export-DeliveryGroup {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$True)]
        $DeliveryGroup,
        [ValidateSet('DC1','DC2','DC3', 'DC4')]
        $DC,
        [ValidateSet('PVS1','PVS2','PVS3', 'PVS4')]
        $PVS,
        [Switch]
        $DisasterRecovery
    )
    BEGIN{      
        $logs = Start-LogHighLevelOperation  -AdminAddress $DC -Source "Studio" -StartTime (Get-Date).ToString() -Text "Exporting Delivery Group `'$DeliveryGroup`'"
        Write-Verbose "Creating log in Studio with ID: $($logs.Id)"

        $Location = $MyInvocation.MyCommand.Path -replace $MyInvocation.MyCommand.Name,""
        set-location $Location

    }
    PROCESS{
        $DG = Get-BrokerDesktopGroup -AdminAddress $DC -Name $DeliveryGroup | SELECT -Property *
        $Results = @()

        if ($DisasterRecovery) {
            if ($DG.PublishedName.StartsWith('XA_FARM1')) {$DG.PublishedName = "XA_BACKUPFARM1" + $DG.PublishedName.Substring(7)}    
        }

        # I am not crazy. I did all of the below in VIM. (literally 4 commands)
        $Properties = @{
            AgentVersion = $DG.AgentVersion
            ApplicationsInUse = $DG.ApplicationsInUse
            AssignedClientName = $DG.AssignedClientName
            AssignedIPAddress = $DG.AssignedIPAddress
            AssociatedUserFullNames = $DG.AssociatedUserFullNames
            AssociatedUserNames = $DG.AssociatedUserNames
            AssociatedUserUPNs = $DG.AssociatedUserUPNs
            AutonomouslyBrokered = $DG.AutonomouslyBrokered
            CatalogName = $DG.CatalogName
            CatalogUid = $DG.CatalogUid
            ClientAddress = $DG.ClientAddress
            ClientName = $DG.ClientName
            ClientVersion = $DG.ClientVersion
            ColorDepth = $DG.ColorDepth
            ConnectedViaHostName = $DG.ConnectedViaHostName
            ConnectedViaIP = $DG.ConnectedViaIP
            ControllerDNSName = $DG.ControllerDNSName
            DNSName = $DG.DNSName
            DeliveryType = $DG.DeliveryType
            Description = $DG.Description
            DesktopConditions = $DG.DesktopConditions
            DesktopGroupName = $DG.DesktopGroupName
            DesktopGroupUid = $DG.DesktopGroupUid
            DesktopKind = $DG.DesktopKind
            DeviceId = $DG.DeviceId
            FunctionalLevel = $DG.FunctionalLevel
            HardwareId = $DG.HardwareId
            HostedMachineId = $DG.HostedMachineId
            HostedMachineName = $DG.HostedMachineName
            HostingServerName = $DG.HostingServerName
            HypervisorConnectionName = $DG.HypervisorConnectionName
            HypervisorConnectionUid = $DG.HypervisorConnectionUid
            IPAddress = $DG.IPAddress
            IconUid = $DG.IconUid
            ImageOutOfDate = $DG.ImageOutOfDate
            InMaintenanceMode = $DG.InMaintenanceMode
            IsAssigned = $DG.IsAssigned
            IsPhysical = $DG.IsPhysical
            LastConnectionFailure = $DG.LastConnectionFailure
            LastConnectionTime = $DG.LastConnectionTime
            LastConnectionUser = $DG.LastConnectionUser
            LastDeregistrationReason = $DG.LastDeregistrationReason
            LastDeregistrationTime = $DG.LastDeregistrationTime
            LastErrorReason = $DG.LastErrorReason
            LastErrorTime = $DG.LastErrorTime
            LastHostingUpdateTime = $DG.LastHostingUpdateTime
            LaunchedViaHostName = $DG.LaunchedViaHostName
            LaunchedViaIP = $DG.LaunchedViaIP
            MachineInternalState = $DG.MachineInternalState
            MachineName = $DG.MachineName
            MachineUid = $DG.MachineUid
            OSType = $DG.OSType
            OSVersion = $DG.OSVersion
            PersistUserChanges = $DG.PersistUserChanges
            PowerActionPending = $DG.PowerActionPending
            PowerState = $DG.PowerState
            Protocol = $DG.Protocol
            ProvisioningType = $DG.ProvisioningType
            PublishedApplications = $DG.PublishedApplications
            PublishedName = $DG.PublishedName
            PvdStage = $DG.PvdStage
            RegistrationState = $DG.RegistrationState
            SID = $DG.SID
            SecureIcaActive = $DG.SecureIcaActive
            SecureIcaRequired = $DG.SecureIcaRequired
            SessionHidden = $DG.SessionHidden
            SessionId = $DG.SessionId
            SessionState = $DG.SessionState
            SessionStateChangeTime = $DG.SessionStateChangeTime
            SessionUid = $DG.SessionUid
            SessionUserName = $DG.SessionUserName
            SessionUserSID = $DG.SessionUserSID
            SmartAccessTags = $DG.SmartAccessTags
            StartTime = $DG.StartTime
            SummaryState = $DG.SummaryState
            Tags = $DG.Tags
            Uid = $DG.Uid
            WillShutdownAfterUse = $DG.WillShutdownAfterUse
        }

        $Results += New-Object PSObject -Property $Properties

    }
    END {
        $FileName = $DeliveryGroup + $(Get-Date -Format yyyyMMddTHHmm) + "DG.xml"
        $Results | export-clixml .\$FileName
    }
}

Export-DeliveryGroup -DeliveryGroup "XA_FARM1DELIVERYGROUP" -DC DC1 -PVS PVS1 -DisasterRecovery