Import-Module "C:\Program Files\Citrix\Provisioning Services Console\Citrix.PVS.SnapIn.dll"
if (-not (Get-PSSnapin | where {$_.Name -Like "*Citrix*"})) {
    Add-PSSnapin Citrix*
}

Function Create-MachineCatalog {
    [CmdletBinding()]
    param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$MahineCatalog,
    [ValidateSet('DC1','DC2','DC3', 'DC4')]
    [ValidateNotNullOrEmpty()]
    [string]$DC = "defaultdc.fqdn:80",
    [ValidateSet('pvs1','pvs3','pvs4', 'pvs5')]
    [ValidateNotNullOrEmpty()]
    [string]$PVS = "defualtpvs",
    $ListOfMachinesToAdd
    )
    BEGIN{
        $MACHINE_CATALOG = $MahineCatalog
        
        $logs = Start-LogHighLevelOperation  -AdminAddress $DC -Source "Studio" -StartTime (Get-Date).ToString() -Text "Migrating Machine Catalog `'$MACHINE_CATALOG`'"
        Write-Verbose "Creating log in Studio with ID: $($logs.Id)"
    }
    PROCESS{
        $Catalog = $null

        try {
            $Catalog = Get-BrokerCatalog -Name $MACHINE_CATALOG -AdminAddress $DC -ErrorAction Stop
        } Catch [Citrix.Broker.Admin.SDK.SdkOperationException] { 
            $Catalog = New-BrokerCatalog  -AdminAddress $DC -AllocationType "Random" -Description $MACHINE_CATALOG `
                                -IsRemotePC $False -LoggingId $logs.Id -MachinesArePhysical $False -MinimumFunctionalLevel "L7_9" `
                                -Name $MACHINE_CATALOG -PersistUserChanges "Discard" -ProvisioningType "PVS" -PvsAddress $pvs -PvsDomain "FQDN.DOMAIN" ` # enter your domain here
                                -Scope @() -SessionSupport "MultiSession"
        }
        Write-Verbose "Grabbed Catalog ID: $($Catalog.Uid)"

        $HyperVisor = Get-BrokerHypervisorConnection | Where {$_.Name -like "PVS STORE NAME"} # ENTER YOUR PVS STORE NAME HERE
        Write-Verbose "Connected to Hypervisor $($HyperVisor.Name) with id: $($HyperVisor.Uid)"

        $HyperVisorMacAddresses = Get-HypVMMacAddress -AdminAddress $DC -LiteralPath "XDHyp:\Connections\PVS STORE NAME"# ENTER YOUR PVS STORE NAME HERE
        Write-Verbose "Grabbing all MAC Addresses and VMIds from $($HyperVisor.Name) with id: $($HyperVisor.Uid)"

        Set-PvsConnection -port 54321 -server $pvs
        Write-Verbose "Connecting to PVS $PVS"

        $SiteId = Get-PvsSite | select -ExcludeProperty SiteId
        Write-Verbose "Connected to PVS $($SiteId)"

        $CollectionID = Get-PvsCollection -CollectionName $MACHINE_CATALOG -SiteId $SiteId.SiteId
        Write-Verbose "Collected Collection information from PVS"

        $PVSDevices = Get-PvsDevice -CollectionId $CollectionID.CollectionId
        Write-Verbose "Collected device information from PVS. All devices with the collection id grabbed."

        $deviceIds = @()
        foreach ($deviceid in $PVSDevice) { $deviceIds += $deviceid.DomainObjectSID; Write-Verbose "Collected $($deviceid.DomainObjectSID)" }
        Write-Verbose "Extracted PVS DevicIds"

        $ExistingMachines = Get-BrokerMachine  -AdminAddress $DC -Filter {(SID -in $deviceIds)}
        Write-Verbose "Checking for existing machines in Machine Catalog: $MACHINE_CATALOG"

        $nonExistingDeviceIDs = @{}

        foreach ($machine in $PVSDevices) {
    
            [boolean] $exists = $False
    
            foreach ($existingMachine in $ExistingMachines) {
                if ($existingMachine.SID -EQ $machine.DomainObjectSID) {
                    Write-Verbose "Machine $($existingMachine.HostedMachineName) already exists"
                    $exists = $True
                    break
                }
            }

            if (-not ($exists)) {
                $VMId = $HyperVisorMacAddresses| ? {$_.MacAddress -eq $machine.DeviceMac.ToString().replace("-",":").tolower()}
                $nonExistingDeviceIDs.Add($VMId.VMId, $machine.DomainObjectSID)
                Write-Verbose "$($machine.DeviceName) does not exist. Device will be created"
            }
        }

        foreach ($SID in $nonExistingDeviceIDs.Keys) {
            try {
                $justAddedMachine = New-BrokerMachine -AdminAddress $DC -CatalogUid $Catalog.Uid -HostedMachineId $SID -HypervisorConnectionUid $HyperVisor.Uid -LoggingId $logs.Id -MachineName $nonExistingDeviceIDs[$SID] -ErrorAction Stop
                Write-Verbose "Machine $($justAddedMachine.MachineName) added to: $MACHINE_CATALOG"

                if ($justAddedMachine.MachineName -match 'pm\d+') {
                    Set-BrokerMachine -InputObject $justAddedMachine -InMaintenanceMode $True
                    Write-Verbose "Machine $($justAddedMachine.MachineName), maintenance mode turned on"
                }

                # TO DO : UNCOMMENT
                #New-BrokerHostingPowerAction -Action Restart -LoggingId $logs.Id -MachineName $justAddedMachine.MachineName | Out-Null
                Write-Verbose "Rebooting $($justAddedMachine.MachineName)"
            } Catch [Citrix.Broker.Admin.SDK.SdkOperationException] {
            
            }
            
        }
    }
    END{
        Stop-LogHighLevelOperation  -AdminAddress $DC -EndTime (Get-Date).ToString() -HighLevelOperationId $logs.Id -IsSuccessful $True
        Write-Verbose "Stopped logging in Studio. ID: $($logs.Id)"
    }
}

Create-MachineCatalog -MahineCatalog "XA_TEST" -Verbose