Import-Module "C:\Program Files\Citrix\Provisioning Services Console\Citrix.PVS.SnapIn.dll"
if (-not (Get-PSSnapin | where {$_.Name -Like "*Citrix*"})) {
    Add-PSSnapin Citrix*
}


Function Add-MachinesToDeliveryGroup {
    [CmdletBinding()]
    param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$DeliveryGroup,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$MahineCatalog,

    [Parameter(Mandatory)]
    [alias("DeliveryController")]
    [ValidateSet('dc1','dc2','dc3', 'dc4')]
    [ValidateNotNullOrEmpty()]
    [string]$DC,

    [Parameter(Mandatory)]
    [ValidateSet('pvs1','pvs2','pvs3', 'pvs4')]
    [ValidateNotNullOrEmpty()]
    [string]$PVS
    )
    BEGIN{
        #$DC += ".shcsd.sharp.com:80"
        $logs = Start-LogHighLevelOperation  -AdminAddress $DC -Source "Studio" -StartTime (Get-Date).ToString() -Text "Migrating Delivery Group `'$DeliveryGroup`'"
        Write-Verbose "Creating log in Studio with ID: $($logs.Id)"
    }
    PROCESS{
        $ExistingDeliveryGroup = $NULL
        try {
            Write-Verbose "Checking if $DeliveryGroup exists"
            $ExistingDeliveryGroup = Get-BrokerDesktopGroup -Name $DeliveryGroup -ErrorAction Stop
            Write-Verbose "$DeliveryGroup exists"
        } Catch [Citrix.Broker.Admin.SDK.SdkOperationException] {
            Write-Verbose "$DeliveryGroup does not exist. Creating delivery group: $DeliveryGroup"
            $ExistingDeliveryGroup = New-BrokerDesktopGroup  -AdminAddress $DC -ColorDepth "TwentyFourBit" -DeliveryType "DesktopsAndApps" -Description $DeliveryGroup `
                                                             -DesktopKind "Shared" -InMaintenanceMode $False -IsRemotePC $False -LoggingId $logs.Id `
                                                             -MinimumFunctionalLevel "L7_9" -Name $DeliveryGroup -OffPeakBufferSizePercent 10 -PeakBufferSizePercent 10 -PublishedName $DeliveryGroup `
                                                             -Scope @() -SecureIcaRequired $False -SessionSupport "MultiSession" -ShutdownDesktopsAfterUse $False -TimeZone "Pacific Standard Time"
        }

        Write-Verbose "Setting Delivery Group zone preferences"
        Set-BrokerDesktopGroup -AdminAddress $DC -InputObject $ExistingDeliveryGroup -LoggingId $logs.Id -PassThru -ZonePreferences @("ApplicationHome","UserHome","UserLocation")

        Write-Verbose "Gathering broker machines to add to delivery group"
        $filter = "(((CatalogName -eq `"$DeliveryGroup`")) -and (SessionSupport -eq `"MultiSession`") -and (InMaintenanceMode -eq `$False))"
        $MachinesInCatalog = Get-BrokerMachine  -AdminAddress $DC -Filter $filter -MaxRecordCount 500

        Write-Verbose "Adding broker machines to delivery group"
        Add-BrokerMachine  -AdminAddress $DC -DesktopGroup $DeliveryGroup -InputObject @($MachinesInCatalog)  -LoggingId $logs.Id

        Write-Verbose "Setting up access policies on delivery group"
        New-BrokerAppEntitlementPolicyRule  -AdminAddress $DC -DesktopGroupUid $ExistingDeliveryGroup.Uid -Enabled $True -IncludedUserFilterEnabled $False -LoggingId $logs.Id -Name $DeliveryGroup

        New-BrokerAccessPolicyRule -AdminAddress $DC -AllowedConnections "NotViaAG" -AllowedProtocols @("HDX","RDP") -AllowedUsers "AnyAuthenticated" -AllowRestart $True `
                                   -DesktopGroupUid $ExistingDeliveryGroup.Uid -Enabled $True -IncludedSmartAccessFilterEnabled $True -IncludedUserFilterEnabled $True -IncludedUsers @() -LoggingId $logs.Id -Name "$($DeliveryGroup)_Direct" | Out-Null

        New-BrokerAccessPolicyRule -AdminAddress $DC -AllowedConnections "ViaAG" -AllowedProtocols @("HDX","RDP") -AllowedUsers "AnyAuthenticated" -AllowRestart $True `
                                   -DesktopGroupUid $ExistingDeliveryGroup.Uid -Enabled $True -IncludedSmartAccessFilterEnabled $True -IncludedSmartAccessTags @() -IncludedUserFilterEnabled $True -IncludedUsers @() -LoggingId $logs.Id -Name "$($DeliveryGroup)_AG" | Out-Null
    }
    END{
        Stop-LogHighLevelOperation  -AdminAddress $DC -EndTime (Get-Date).ToString() -HighLevelOperationId $logs.Id -IsSuccessful $True
        Write-Verbose "Stopped logging in Studio. ID: $($logs.Id)"
    }
}


Add-MachinesToDeliveryGroup -DeliveryGroup "DELIVERYGROUP" -MahineCatalog "MACHINECATALOG" -DC "DC1" -PVS "PVS1" -Verbose