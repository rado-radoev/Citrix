
##########################################################################################################################################
#
# Name:				Check server status and recover
# Author:			superklamer
# Version:			1.4
# Last Modified By:	
# Last Modified On:	12/13/2018 (see history for change details)
#
#
# IMPORTANT
# THIS COMMAND EXPORTS THE SERVICE ACCOUNT CREDNTIALS TO AN ENCRYPTED FILE THAT WILL BE USED TO CONNECT TO VSPHERE
# WITHOUT THAT FILE IN THE SCRIPT ROOT FOLDER HALF OF THE FUNCTIONS WILL NOT WORK
# Get-Credential | Export-Clixml "citrixservice.clixml"
#
#
# 
# History: 
# 12/13/2018: Version 1.0
#             Original copy
###########################################################################################################################################

<#
.SYNOPSIS 
	Checks server status and tries to recover 

.DESCRIPTION
	Checks server status and tries to recover

    There a lot of states a Citrix server or VDI can go to and get stuck. This script will go through all Delivery Groups and will try to 
    recover servers that are stuck in "Unmanaged" state, or are in "Uknown" state. 

.PARAMETER 
	DeliveryGroup accepts Desktop Groups to check server status 

.PARAMETER
    AdminAddress is the FQDN for a Delivery Controller

.EXAMPLE
    powershell.exe -ExecutionPolicy RemoteSigned -file <path to script>\CheckServerStatus_v1.0.ps1
    
.NOTES
	Run script from task scheduler or manually
#> 


#region Write log file
Function Write-Log
{
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $False, HelpMessage = "Log Level")]
		[ValidateSet("INFO", "WARN", "ERROR", "FATAL", "DEBUG")]
		[string]$Level = "INFO",
		[Parameter(Mandatory = $True, Position = 0, HelpMessage = "Message to be written to the log")]
		[string]$Message,
		[Parameter(Mandatory = $False, HelpMessage = "Log file location and name")]
		[string]$Logfile = "C:\Logs\ServerHealthCheck_$(Get-Date -Format yyyyMMdd).log"
	)
    BEGIN {
    	$Stamp = (Get-Date).toString("yyyy/MM/dd HH:mm:ss")
	    $Line = "$Stamp $Level $Message`r`n"
    }
    PROCESS {
    	If ($Logfile) {
            [System.IO.File]::AppendAllText($Logfile, $Line)
	    } Else {
		    Write-Output $Line
	    }
    }
    END {}
} 
#endregion

#region Connect-ViShpere
Function Connect-ViShpere ($vCenterName,$credfile)  {
    try {
        Connect-Viserver $vCenterName -Credential (Import-clixml -Path $credfile) -ErrorAction Stop | Out-Null
        Write-Log "Connected to vcenter: $vCenterName"
     } catch {
        Write-Log "Could not connect to vcenter: $vCenterName"
        Write-Log "$($Error[0].Exception)"
     }
}
#endregion

#region Send-mail
Function Send-Mail{
    [CmdletBinding()]
    Param (
		[Parameter(Mandatory)]
		$msgsubject,
		[Parameter(Mandatory)]
		$msgbody
	)

	#SMTP server name
	$smtpServer = "SMTP.SERVER.ADDRESS"

	#Creating a Mail object
	$msg = new-object Net.Mail.MailMessage

	#Creating SMTP server object
	$smtp = new-object Net.Mail.SmtpClient($smtpServer)

	#Email structure 
	$msg.From = "SENDING.FROM.EMAL"
    $msg.To.Add("SENDING.TO.EMAIL")
    $msg.ReplyTo = "SENDING.TO.EMAIL"
	$msg.subject = $msgsubject
	$msg.IsBodyHTML = $true
	$msg.body = $msgbody 
	$smtp.Send($msg)
} 
#endregion

#region Get-Location
Function Get-Location() {

    # Location[0] = $vcenter
    # Location[1] = $adminAddress
    $location = @()
    $vcenter = @{}
    $adminAddress = @{}
    $computerName = $ENV:COMPUTERNAME

    # All possible ViSphere farms to connect to
    $vcenters = @{farm1 = "famr1"
                  farm2 = "farm2"
                  farm3 = "farm3"
                  farm4 = "farm4"
                }

    $DCs = @{dc1 = "dc1"
             dc2 = "dc2"
             dc3 = "dc3"
             dc4 = "dc4"
            }

    # Grab the first 4 characters from the computer that the script is being run on. Usually that is a development machine that sits in the same datacenter
    $prefix = $computerName.ToLower().Substring(0, 4)
    
    # The location where the vcenter and the dc are located will be depnding on the hostname prefix, where the script is being run from.
    if ($prefix.StartsWith("farm1") -or $prefix.StartsWith("farm2") ) { 
        if ($prefix.StartsWith("farm1")) {
            $vcenter.Add("vcenter", $vcenters.farm1)
            $adminAddress.Add("dc", $DCs.dc1)
        } elseif ($prefix.StartsWith("farm2")) {
            $vcenter.Add("vcenter", $vcenters.farm2)
            $adminAddress.Add("dc", $DCs.dc2)
        }
    } else {
        $prefix = $prefix.Substring(1) # in this case we only needed the 3 characters omitting the very first character
        if ($prefix -eq "farm3") {
            $vcenter.Add("vcenter", $vcenters.farm3)
            $adminAddress.Add("dc", $DCs.dc3)    
        } elseif ($prefix -eq "farm4") {
            $vcenter.Add("vcenter", $vcenters.farm4)
            $adminAddress.Add("dc", $DCs.dc4)
        }
    }

    $location += $vcenter
    $location += $adminAddress

    # An error will be thrown if the $vcenter variable is empty. After all how should we know where to connect to?!? Huh ...
    if (-not $location.vcenter) {
        Write-Log -Level ERROR -Message "Could not get correct vcenter from current computer hostname. Verify curren computer hostname prefix is soc, rsm, ?phx or ?rsm"
        throw (New-Object -TypeName System.ArgumentNullException -ArgumentList "`$vcenter cannot be empty. Please provide the `$vcenter parameter or check the current machine prefix")
    }

    # An error will be thrown if the $vcenter variable is empty. After all how should we know where to connect to?!? Huh ...
    if (-not $location.dc) {
        Write-Log -Level ERROR -Message "Could not get correct delivery controller from current computer hostname. Verify curren computer hostname prefix is soc, rsm, ?phx or ?rsm"
        throw (New-Object -TypeName System.ArgumentNullException -ArgumentList "`$DC cannot be empty. Please provide the `$DC parameter or check the current machine prefix")

    }

    # A two index array containing the vcenter name and the dc name
    return $location
}
#endregion

#region Load Snapins
Function Load-Snapins() {
    Add-PSSnapin Citrix.*

    #VMWare PowerCli must be installed on the system
    $VMWareModuleList = @(
        "VMware.VimAutomation.Core",
        "VMware.VimAutomation.Vds",
        "VMware.VimAutomation.Cloud",
        "VMware.VimAutomation.PCloud",
        "VMware.VimAutomation.Cis.Core",
        "VMware.VimAutomation.Storage",
        "VMware.VimAutomation.HA",
        "VMware.VimAutomation.vROps",
        "VMware.VumAutomation",
        "VMware.VimAutomation.License")
    ForEach ($module in $VMWareModuleList) {
        Import-Module $module
    }   
}
#endregion

#region Check-Server
Function Check-Server() {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)]
        $machine,
        $deliveryGroup
     )
    BEGIN{
        $computer = $machine.HostedMachineName
	    $inMaintenanceMode = $machine.InMaintenanceMode
        $vm = get-vm -Name $computer

    }
    PROCESS{

        $machineState = "Normal"

        #region Check if VM is powered off, then turn it on
        if ($vm.PowerState -ne "PoweredOn") {
            Write-Log "$computer : PoweredOff"
            Write-Log "$computer : Powering on"
            Start-VM -VM $computer | Out-Null
            $machineState = "PoweredOff"
        }
        #endregion

        #region Check if VM is powered on and unresponsive, then reset it
        If ( ($vm.PowerState -eq "PoweredOn") -AND !(Test-Connection -ComputerName $computer -quiet -count 2) ) {
            Write-Log "$computer : Unresponsive"
            Write-log "$computer : Powering off"
            Stop-VM -VM $computer -Kill -Confirm:$false -RunAsync
            Start-Sleep -s 3
            Write-Log "$computer : Powering on"
            Start-VM -VM $computer -Confirm:$false -RunAsync | Out-Null
            $machineState = "Unresponsive"
	    }
        #endregion

        # region Check if maintenance mode, if so (and no user sessions) restart and remove maintenance
        # only run this against VDI DELIVERY GROUP
        # We didn't want to touch XENAPP servers that could be in maintenance in purpose
        # Instead this code only executes if we hit a delivery group that has VDI machine in it.
        # We don't want VDI machines to sit in Maintenance mode with no user sessions on them.
        # That would be a waster of resources. They need to be removed from Maintenance and bounced. (if no users of course)
        if ($deliveryGroup.ToLower() -eq "VDI_DELIVERY_GROUP") {   
            If ($inMaintenanceMode) {
                $users = $machine.SessionCount
                If ($users -eq 0) {
                    Write-Log "$computer : sessions: $users"
                    Write-log "$computer : Powering off"
                    Stop-VM -VM $computer -Kill -Confirm:$false
                    Start-Sleep -s 3
                    Write-Log "$computer : Powering on"
                    Start-VM -VM $computer
                    $machine | Set-BrokerMachineMaintenanceMode -MaintenanceMode $false
                    Write-Log "Machine is in Maintenance mode"
                    $machineState = "MaintenanceMode"
                } else {
                    Write-Log "Machine is in Maintenance mode with sessions"
                    $machineState = "MaintenanceModeWithSessions"
                }
            }
        }
        #endregion

        #region Check if not rebooted, and if no users on, reboot. If not and users, put in maintenance
        # CURRENTLY DISABLED. LEFT FOR FUTURE NEEDS
        # This can be turned on if servers need to restart daily and if not restarted in 24h, make sure they are rebooted
        <#try {
            $lastBoot = (gwmi -comp $computer -class win32_operatingsystem -ErrorAction Stop | select __SERVER,@{label="LastBoot";expression={$_.ConvertToDateTime($_.LastBootUpTime)}}).LastBoot
            If ( ((get-date) - $lastBoot).Hours -gt 24 ) {
                $users = $machine.SessionCount
                If ($users -eq 0) {
                    Write-Log "$computer : sessions: $users"
                    Write-log "$computer : Powering off"
                    Stop-VM -VM $computer -Kill -Confirm:$false
                    Start-Sleep -s 3
                    Write-Log "$computer : Powering on"
                    Start-VM -VM $computer
                    Write-Log "Machine is with Uptime Greater then one day"
                    $machineState = "UptimeGreaterThan1Day"
                } else {
                    $machine | Set-BrokerMachineMaintenanceMode -MaintenanceMode $true
                    Write-Log "Machine is with Uptime Greater then one day with sessions"
                    $machineState = "UptimeGreaterThan1DayWithSessions"
                }
            }
        } catch {
            Write-Log "Machine is Unresponsive"
            $machineState = "Unresponsive"
        }#>
        #endregion

        #region Check if PowerState is unknown, in which it won't take connections
        If ($machine.PowerState -eq "Unknown") {
            Write-Log "Machine is in Power State Unknown"
            $machineState = "PowerStateUnknown"
        }
        #endregion
    }
    END{
        Write-Log "Server: $computer status is: $machineState"
        return $machineState
    }
}
#endregion

function html-color($computerName, $color, $result) {
    return "$computerName = <span style='background-color: DarkBlue;'><font color='$color'><b>$result</b></font></span><br>"
}

#region Main
function Start-Main {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [String]$deliveryGroup,
        [Parameter(Mandatory)]
        [String]$AdminAddress
    )
    
    begin {

        $DGMachines = Get-Brokermachine -DesktopGroupName $deliveryGroup -adminaddress $AdminAddress
        Write-Log "Checking server status on $deliveryGroup"
    }
    
    process {
        ForEach ($machine in $DGMachines) {
            # If the machine is a PM, leave it alone
            $computerName = $machine.HostedMachineName
            # Maintenance servers that end with PM and a digit at the end will be skipped. We don't want to restart them
            if ($computerName -match "\w+PM\d{1,2}" -or $computerName -eq "") {Write-Log "Server: $computerName is PM. Skipping ..."; continue}
            # Phisical machines will be ignored too
            if ($machine.IsPhysical) {Write-Log "Server: $($machine.DNSName) is Phisical. Better not mess with it. Skipping ..."; continue}
             
            $result = Check-Server -machine $machine -deliveryGroup $deliveryGroup
            Switch ($result) {
                PoweredOff { $resOutput = html-color -computername $computerName -color "Red" -result $result; break}
                Unresponsive { $resOutput = html-color -computername $computerName -color "Red" -result $result; break}
                MaintenanceMode { $resOutput = html-color -computername $computerName -color "Yellow" -result $result; break}
                MaintenanceModeWithSessions { $resOutput = html-color -computername $computerName -color "Orange" -result $result; break}
                UptimeGreaterThan1Day { $resOutput = html-color -computername $computerName -color "Yellow" -result $result; break}
                UptimeGreaterThan1DayWithSessions{ $resOutput = html-color -computername $computerName -color "Orange" -result $result; break}
                PowerStateUnknown { $resOutput = html-color -computername $computerName -color "Yellow" -result $result; break}
                default { $resOutput = html-color -computername $computerName -color "LawnGreen" -result $result; break}
            }
            $resultTable +=  $resOutput
        }
    }
    
    end {
        return $resultTable
    }  
#endregion
}





Load-Snapins

# log file will be generated in C:\Logs
if (-not (Test-Path "C:\Logs")) {New-Item -ItemType Directory -Path "C:\Logs"}
Write-Log "--- STARTING HEALTH CHECK ---"

$currentLoc = Get-Location
$VCENTER = $currentLoc.vcenter
Write-Log "Vcenter: $VCENTER"
$ADMINADDRESS = $currentLoc.DC
Write-Log "DC: $ADMINADDRESS"

$msgBody = @()

# Grabbing all delivery groups that do not match certain criteria. Can be either the name of the Delivery Group or a Tag assigned to it. 
$allDeliveryGroups = Get-BrokerMachine -AdminAddress $ADMINADDRESS | where {$_.Name -notmatch "nonprod|maintenance|test|" -and $_.Tags -notcontains "NonProd"}
$deliveryGroupsAlreadyVisited = @()

# If the xml file is missing we'll not be able to connect to vsphere and most of the remediation steps will not work
Connect-ViShpere -vcentername $VCENTER -credfile "C:\Scripts\citrixservice.clixml"

# Looping throug each delivery group and if we haven't visited it already, we'll run the server check against it
foreach ($deliveryGroup in $allDeliveryGroups) { 
    if ($deliveryGroup.DesktopGroupName -and (-not($deliveryGroupsAlreadyVisited.Contains($deliveryGroup.DesktopGroupName)))) {
        $deliveryGroupsAlreadyVisited += $deliveryGroup.DesktopGroupName
        $msgBody += Start-Main -deliveryGroup $deliveryGroup.DesktopGroupName -AdminAddress $ADMINADDRESS
    }
}

Disconnect-ViServer -Server $vcenter -Force -Confirm:$false
Write-Log "Disconnected from vcenter: $vcenter"

Write-Log "Sending e-mail"

Send-Mail -msgsubject "Daily Server Status Monitor" -msgbody $msgBody

Write-Log "E-mail sent. Goodbye."
Write-Log "--- ENDING HEALTH CHECK ---"