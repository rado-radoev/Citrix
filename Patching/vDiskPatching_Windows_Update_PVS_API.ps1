<#
	.NOTES
	===========================================================================
	 Created on:   Continuous updating
	 Created by:   superklamer
	===========================================================================
	.DESCRIPTION
        This script is an attempt to automatically patch vDisk. It will automatically connect to PVS,
        open maintenance on all the vDisks, connect to vShpere, boot the servers, run the Windows patching .... and that's it.
        It stops there. It turned out it is difficult to track the progress of Windows updates prior server 2012. I thought about
        using sockets or REST API calls to track the status, but Server 2008 and powershell v3 are missing some functionality 
        that made it very difficult to maintaint the update status past a reboot. ... And I kind of left it there, but the rest is working

        it took a lot of time and digging through the PVS api to do all those things, so I hope it is useful to anybody
#>


#region Globals
$vDisksCount = 0
$vDiskInfoToPM = New-Object System.Collections.Hashtable

$funny = Get-Content -Raw .\funny.txt -ErrorAction SilentlyContinue # just a stupid ASCII art. Don't really need that.

$PVSControllers = @{
    "PVSFARM1" = @("PVS1", "PVS2", "PVS3", "PVS4")
    "PVSFARM2" = @("PVS1", "PVS2", "PVS3", "PVS4")
    "PVSFARM3" = @("PVS1", "PVS2")

}

# Depending on the computer prefix tha the script is running on we'll connect to that PVS farm
# in this case we are using the first 3 characters 
$Prefix= $ENV:COMPUTERNAME.Substring(0,4)
$RandomPVSController = Get-Random -Maximum ($PVSControllers.$Prefix).Count
$SelectedPVSController = ($PVSControllers.$Prefix).get($RandomPVSController)
#endregion

#region Load snapins and modules
Function Load-Snapins {
    Add-PSSnapin Citrix*

    # Loading PVS snapins from that PVS controller
    if (!(Get-Module -Name "Citrix.PVS.SnapIn")) {
		if (Test-Path -Path "\\$SelectedPVSController\c$\Program Files\Citrix\Provisioning Services Console\Citrix.PVS.SnapIn.dll")
		{
			Import-Module "\\$SelectedPVSController\c$\Program Files\Citrix\Provisioning Services Console\Citrix.PVS.SnapIn.dll"
		} 
    }

    if (!(Get-Module -Name "Citrix.PVS.SnapIn")) { # Try to load the Snnapin from local machineif all other attepmpts fail
        Import-Module "C:\Program Files\Citrix\Provisioning Services Console\Citrix.PVS.SnapIn.dll"
    }

    # POWER-CLI POSH SDK NEEDS TO BE INSTALLED ON THE MACHINE FOR THIS TO WORK
    # Load vSphere snapins and try to boot straight from the mothership
    if (!(Get-Module -Name VMware.VimAutomation.Core)) {
        if (Test-Path "C:\Program Files (x86)\VMware\Infrastructure\PowerCLI\Scripts\Initialize-PowerCLIEnvironment.ps1") {
            & "C:\Program Files (x86)\VMware\Infrastructure\PowerCLI\Scripts\Initialize-PowerCLIEnvironment.ps1" 
        }
    }
    
}
#endregion

#region Promote Image
Function Promote-Image {
    [CmdletBinding()]
    param (
    [parameter(Mandatory=$true)]
    [hashtable]$vDiskInfoToPM,
    [parameter(Mandatory=$true)]
    [String]$theRealPM,
    [parameter(Mandatory=$true)]
    [String]$site,
    [parameter(Mandatory=$true)]
    [String]$store
    )
    
    begin { 
        $vdisk = ($vDiskInfoToPM | Where { $_.Keys -eq $theRealPM }).Values
    }
    
    process {
        Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false
        Connect-Viserver <#VCENTER#> -username <#USERNAME#> -password <#PASSWORD#> -ErrorAction SilentlyContinue | Out-null
        $vmStopped = Stop-VM -VM $theRealPM -Confirm:$false -RunAsync
        
        if ($vmStopped.PowerState -ne "PoweredOff") {
            # wait for that machin to power off
            $wait = 10
            while ($wait -ge 1 -and (Test-Connection -ComputerName $theRealPM -Quiet -Count 1)) {
                Start-Sleep 2
                $wait--   
            }
        }
        
        # we don't have to be connected to vSphere anymore. 
        # if later on needed we can reconnect
        $vSphere = @{
            "vSphere1" = "VCENTER1"
            "vSphere2" = "VCENTER2"
            "vSphere3" = "VCENTER3"
        }
        # Depending on the computer prefix tha the script is running on we'll connect to that PVS farm
        # in this case we are using the first 3 characters 
        $viServer = $($vSphere[$theRealPM.Substring(0, 4)])
        Disconnect-Viserver -Server $viServer -Force -Confirm:$false
        
        
        Invoke-PvsPromoteDiskVersion -Name $vdisk.DiskLocatorId -SiteName $site -Store $store -Test 
    }

    end{
    }
}
#endregion

#region Restart-PM
Function Restart-PM {
    [CmdletBinding()]
    Param(
        $theRealPm
    )
    
    begin {
    }
    
    process {
        if (Get-Module -Name "VMware.VimAutomation.Core") {
                
            # Connect-VIServer vSphere1
            Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false
            $vSphere = @{
                "vSphere1" = "VCENTER1"
                "vSphere2" = "VCENTER2"
                "vSphere3" = "VCENTER3"
            }
            $viServer = $($vSphere[$theRealPM.Substring(0, 4)])

            Connect-Viserver $viServer -username <#USERNAME#> -password <#password#> -ErrorAction SilentlyContinue | Out-null
            Restart-VM -VM $theRealPM -Confirm:$false -RunAsync

            # we don't have to be connected to vSphere anymore. 
            # if later on needed we can reconnect
            Disconnect-Viserver -Server $viServer -Force -Confirm:$false
     
        } else {
            Write-Host "VMware.VimAutomation.Core Module not loaded"
            Write-host "Canot boot the PM. Attepted to boot from PVS, XenDekstop, vSphere - failed."
            Write-host $funny
        }
    }
    END{}
}
#endregion

#region PM PowerOn
function PowerOn-PM {
    [CmdletBinding()]
    param (
        $theRealPM    
    )
    
    begin {
        $pmBooted = $false
    }
    
    process {
        # Checking to see if PM is booted
        if (Test-Connection -ComputerName $theRealPM -Quiet -Count 1) {
            $pmBooted = $true
            Restart-PM -theRealPm $theRealPM
        }
        
        # If the PM is not powered on
        if (!($pmBooted)) {
            $pmBoot = Start-PvsDeviceBoot -DeviceName $theRealPM
        
            # wait for the PM to boot for 3 minutes and if it failes continue ...
            $bootAttempts = 0
            while ($pmBoot.State -eq 0 -and $bootAttempts -lt 3) { 
        
                # display completed percentage.
                $percentFinished = Get-PvsTaskStatus -Object $pmBoot
                Write-Host "$($percentFinished.ToString())% finished"
                if ($percentFinished -lt 100) {
                    Start-Sleep -Seconds 5 # TO DO: CHANGE THIS BACK TO 60
                }
            
                $pmBoot = Get-PvsTask -Object $pmBoot
            
                $bootAttempts++

            }
        
            # check if task completed
            # often it returns false positive. Check for MapiExceptions too
            $exceptionExists = $pmBoot.MapiException.Contains("ErrorCode")
            if ($pmBoot.State -eq 2 -and (!($exceptionExists))) { 
                Write-Host "PVS Boot successful"
            } else {
                Write-Host "PVS Boot failed"
            }

            # dobule check the OS is booted. If WMI is up and responding to queries, assuming the OS is operational
            # Test-Connection uses WMI. Assuming it returns something the OS is good
            if (Test-Connection -ComputerName $theRealPM -Quiet -Count 1) {
                $pmBooted = $true
            } else {
                $pmBooted = $false
            }
        }

        # computer did not boot
        # attempt to boot with Get-broker
        if (!($pmBooted)) {
            # data controller selected depending on the PM name
            $dataControllers = @{
                "TST" = "DC1"
                "PST" = "DC2"
                "RST" = "DC3"
            }
			Try {
				New-BrokerHostingPowerAction -Action TurnOn -MachineName $theRealPM -AdminAddress "$($dataControllers[$theRealPM.Substring(0, 4)]).FQDN.com" -ErrorAction SilentlyContinue
				$pmBootState = Get-BrokerHostingPowerAction -MachineName $theRealPM -AdminAddress "$($dataControllers[$theRealPM.Substring(0, 4)]).FQDN.com" -ErrorAction SilentlyContinue

				# give the machine some time to boot
				# most of the PMs are not added in the Machine Catalogs 
				# and they can't be powered on with Get-Broker
				if ($pmBootState) {
					$counter = 10
					while ($pmBootState.State -ne "Completed" -and $counter -gt 1) {
						$counter--
						Start-Sleep -Seconds 20

						if (Test-Connection -ComputerName $theRealPM -Quiet -Count 1) {
							$pmBooted = $true 
						}

						$pmBootState = Get-BrokerHostingPowerAction -MachineName $theRealPM -AdminAddress "$($dataControllers[$theRealPM.Substring(0, 4)]).FQDN.com" -ErrorAction SilentlyContinue
					} 
				}
			} catch {
				$pmBooted = $false
				Write-Host "PM Not found in any machine groups. Cannot boot! Exhausting options."
			}
            


        }

        if (!($pmBooted)) {
            Write-host "Could not PowerOn $theRealPM. Tried XenaApp and PVS. Last chance ... Trying vSphere"

            if (Get-Module -Name "VMware.VimAutomation.Core") {
                
                # Connect-VIServer 
                Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false
                $vSphere = @{
                    "vSphere1" = "VCENTER1"
                    "vSphere2" = "VCENTER2"
                    "vSphere3" = "VCENTER3"
                }
                $viServer = $($vSphere[$theRealPM.Substring(0, 4)])

                Connect-Viserver $viServer -username <#USERNAME#> -password <#PASSWORD#> -ErrorAction SilentlyContinue
                $vmSterted = Start-VM -VM $theRealPM -Confirm:$false #-RunAsync
  
                $wait = 10
                Start-Sleep -Seconds $wait              
            
                if ((Get-VM -Name $theRealPM).PowerState -eq "PoweredOn") {
                    # wait for that machine to power 
                    while ($wait -ge 1 -and -not (Test-Connection -ComputerName $theRealPM -Quiet -Count 1)) {
                        Start-Sleep 20
                        $wait--   
                    }
                }

                # we don't have to be connected to vSphere anymore. 
                # if later on needed we can reconnect
                Disconnect-Viserver -Server $viServer -Force -Confirm:$false

                if (Test-Connection -ComputerName $theRealPM -Quiet -Count 1) {
                    $pmBooted = $true
                } else {
                    $wait = 10
                    while ($wait -ge 1 -and -not (Test-Connection -ComputerName $theRealPM -Quiet -Count 1)) {
                        Start-Sleep 20
                        $wait--   
                    }
                    if (Test-Connection -ComputerName $theRealPM -Quiet -Count 1) {
                        $pmBooted = $true
                    } else 
                    {
                        $pmBooted = $false
                        Write-Host "We just can't connect to that PM. Quitting ..."
                        Write-Host $funny
                    }
                }
                
            } else {
                Write-Host "VMware.VimAutomation.Core Module not loaded"
                Write-host "Canot boot the PM. Attepted to boot from PVS, XenDekstop, vSphere - failed."
                Write-host $funny
            }
        }
    }
    
    end {
        return $pmBooted
    }
}
#endregion


#region Update-Comment
function Update-Comment {
    [CmdletBinding()]
    param (
    [parameter(Mandatory=$true)]
    [boolean]$hasMaintenance,
    [parameter(Mandatory=$true)]
    $vdisk
    )
    
    begin {
        $maintDetlaCreated = $false
    }
    
    process {
        if ($hasMaintenance) {
            # Maint already exists update description and include month/year patching - Automated.
            # What's date. I keep forgetting
            $today = Get-Date
            $vdiskOldDesc = $vdiskDeltas[0].Description
            $vdiskNewDesc = "$($vdiskOldDesc)$((Get-Culture).DateTimeFormat.GetAbbreviatedMonthName($today.Month))/$($today.Year) patching - Automated"
            
            if ($vdiskOldDesc.Length -gt 0) {
                $vdiskNewDesc =  "$($vdiskOldDesc)`t$((Get-Culture).DateTimeFormat.GetAbbreviatedMonthName($today.Month))/$($today.Year) patching - Automated"
            } 

           
            if ($vdiskNewDesc.Length -lt 250) {
                $o = Get-PvsDiskVersion -DiskLocatorId $vdisk.DiskLocatorId -Version $vdiskDeltas[0].Version -Fields Description
                $o.Description = $vdiskNewDesc
                Set-PvsDiskVersion -DiskVersion $o -Version $vdiskDeltas[0].Version 
                $null = Write-Host "Maintenance delta - $maintName already exists on vdisk: $($vdisk.Name). Updated comments."
            } else {
                $null = Write-Host "Maintenance delta - $maintName already exists on vdisk: $($vdisk.Name). Comments char limit reached. Will not add comments."
            }
            $maintDetlaCreated = $true
        }

            # check one more time
            $vdiskDeltas = Get-PvsDiskVersion -DiskLocatorId $vdisk.DiskLocatorId
        
            if ($vdiskDeltas[0].CanPromote) { # if vdisk is in maint
                $maintDetlaCreated = $true
            } else {
               $maintDetlaCreated = $false
            } 
    }    
    end {
        return $maintDetlaCreated
    }
}
#endregion

#region Create-Maintenance
function Create-Maintenance {
    [CmdletBinding()]
    param (
    [parameter(Mandatory=$true)]
    [boolean]$hasMaintenance,
    [parameter(Mandatory=$true)]
    $vdisk
    )
    
    begin {
        $maintDetlaCreated = $false
    }
    
    process {
        # What's date. I keep forgetting
        $today = Get-Date
            
        if (!($hasMaintenance)) {  
            #create a new maintenance and add descr if successful
            Try {
                $isMaintenanceCreated = New-PvsDiskMaintenanceVersion -DiskLocatorName $vdisk.DiskLocatorName -SiteName $site -StoreName $store.StoreName
                if ($isMaintenanceCreated -ne $null) {
                    
                $lastind = ($isMaintenanceCreated.Name).LastIndexOf(".")
                $maintName = ($isMaintenanceCreated.Name).Substring(0, $lastind)
                $null = Write-Host "New delta - $maintName created on vdisk: $($vdisk.Name)"

                $vdiskNewDesc = $vdiskDeltas[0].Description = "$((Get-Culture).DateTimeFormat.GetAbbreviatedMonthName($today.Month))/$($today.Year) patching - Automated"
                $vDiskVersionUpdated = Get-PvsDiskVersion -DiskLocatorId $vdisk.DiskLocatorId
                $o = Get-PvsDiskVersion -DiskLocatorId $vdisk.DiskLocatorId -Version $vDiskVersionUpdated[0].Version -Fields Description
                $o.Description = $vdiskNewDesc
                Set-PvsDiskVersion -DiskVersion $o -Version $vDiskVersionUpdated[0].Version 

                $maintDetlaCreated = $true

                } else {
                    Write-Error "Maintenance could not be created"
                    Write-Host $funny
                }
            } Catch {
                Write-Error "Maintenance could not be created"
                Write-Host $funny
            }
        } else {
           Update-Comment -hasMaintenance $hasMaintenance -vdisk $vdisk 
        }
    }    
    end {
        return $maintDetlaCreated
    }
}
#endregion

 
#region Start-Patching - main function to open maintenance and start patching PMs
Function Start-Patching {
    [CmdletBinding()]
    Param()
    BEGIN{ }
    PROCESS{

        # Type: 1 when it performs test of Disks, 2 when itperforms maintenance on Disks, 
        # 3 when it has a Personal vDisk, 4 when it has aPersonal vDisk and performs tests, 0 otherwise. 
        # Min=0, Max=4, Default=0
        $vDiskType = @{
            0 = "Production"
            1 = "Test"
            2 = "Maintenance"
            3 = "Personal"
        }

        Load-Snapins
        
        # TO DO: Add user to perform the log in action 
        Set-PvsConnection -Server $SelectedPVSController -Port 54321 -PassThru
        
        $stores = Get-PvsStore
        $store = $stores | where {$_.StoreName -match "PROD" -or $_.StoreName -match "TEST" -and -not ($_.StoreName -match "REPL" -or $_.StoreName -match "Local" -or $_.StoreName -match "Pilot")}
            
        if ($store.Count -ne 1) {
            Write-host "Something went wrong and I picked up multiple stores. I paniced and bailed on that PVS Controller $pvsController. Sooorryyy"
            Break
        }         
            
        $site = (Get-PvsSite).sitename

        $vdisks = Get-PvsDiskInfo -SiteName $site -storeName $store.storename
        $vDisksCount = $vdisks.Count
        
        foreach ($vdisk in $vdisks) {
            $hasMaintenance = $false # Control variable. Assuming there is no maintenance opened
            $isPMConnectedToMaint = $false # Control variable. Assuming there is no pm powered on
            $devicesUsingVdisk = Get-PvsDeviceInfo -DiskLocatorId $vdisk.DiskLocatorId | where {$_.Name -match "PM\d+"} # Check to see if there are any devices using the vDisk.            
            $theRealPM = $null # Make sure we have the correct PM

            if (!($devicesUsingVdisk)) { continue } # If no devices are attached to the vdisk move on
        
            $vdiskDeltas = Get-PvsDiskVersion -DiskLocatorId $vdisk.DiskLocatorId
        
            if ($vdiskDeltas[0].CanPromote) { # if vdisk is in maint
                $hasMaintenance = $true

                if ($vdiskDeltas[0].DeviceCount -gt 0) {
                    $isPMConnectedToMaint = $True    
                }
            } 


            # if there is no maint opened, open one and set description to month/year patching - Automated
            if ($hasMaintenance) {
                Update-Comment -hasMaintenance $hasMaintenance -vdisk $vdisk
            } else {
                Create-Maintenance -hasMaintenance $hasMaintenance -vdisk $vdisk
            }

            If (!($isPMConnectedToMaint)) {
                Write-Host "PM is not booted or not connected to maint"

                # find the PM 
                $pm = $devicesUsingVdisk
        
                foreach ($p in $pm) {
                    $deviceInfo = Get-PvsDevice -DeviceName $p.DeviceName
                    if ($deviceInfo.Type -eq 2 -and $deviceInfo.Enabled -eq $True) {
                        $theRealPM = $deviceInfo.DeviceName
                        Write-Host "Found the PM: $($deviceInfo.DeviceName). Currently set to: $($vDiskType[[int]$deviceInfo.Type])"
                        $vDiskInfoToPM.Add($theRealPM, $vdisk)
                    }      
                }

                PowerOn-PM -theRealPM $theRealPM       
           }
           
            # If no PM is found throw an error 
            if (!($theRealPM)) {
                #throw [System.Exception]::new("Cannot create maintenance. NO PM found! Please contact DL.EMAIL@COMPANY.COM for further assistance")
                Write-Host "Cannot create maintenance. NO PM found! Please contact DL.EMAIL@COMPANY.COM for further assistance"
            }
        }
        Clear-PvsConnection 
    }
    END{}
}
#endregion

Start-Patching