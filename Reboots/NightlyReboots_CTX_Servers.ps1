##########################################################################################################################################
#
# Name:				Nightly Server Reboots 7.x
# Author:			superklamer
# Version:			1.4
# Last Modified By:	
# Last Modified On:	12/28/2017 (see history for change details)
# 
# History: 
# 12/28/2017: Version 1.0
#             Original copy
# 01/9/2018: Version 1.1
#             Added functionality to target specific Desktop Groups for restart
#             Updated Synopsis
#             Updated Logging
# 01/15/2018: Version 1.2
#              Fixed even/odd days detection
#              Modified restart time calculation
# 01/16/2018: Version 1.3
#              Added additional message to the user 30 seconds prior reboot
#              Added additional logging when sending messages to the users
#              Bug fixes
# 01/17/2018: Version 1.4
#              Bug fixes
# 
##########################################################################################################################################

<#
.SYNOPSIS 
	Disables new user sessions, retrieves all user sessions, sends user messages, logs off users and reboots server according to a schedule

.DESCRIPTION
	Disables new user sessions, retrieves all user sessions, sends user messages, logs off users and reboots server according to a schedule

	The script is checking the day of the week. On even days, servers ending with even number are restarted. On odd days, servers ending on
    odd number are restarted. Script also check the Delivery Group Tags, to determine if the server should be restarted daily, once a week 
    or it is excluded from restarts. Servers are restarted at specific time. Sessions are drained until restart one hour prior to restart
    time. If no users are logged in at that time, the server is restarted. Else the script keeps retrying and sending messages to the users
    every 60, 30, 20, 10, 5 minutes. Once time is up, the users still logged in are kicked off and server is restarted. 
    Script creates logs for each individual server in a YEAR/MONTH/DAY folder strucutre. Master log is also created in the destination.
    After reboot all servers are checked against Citrix services. Servers with Stopped or not working services are tagged in the log file.
    Send e-mail functionality available, but not implemented. 

.PARAMETER 
	Filter accepts Desktop Groups separated by |

.PARAMETER
    Only used with Filter parameter. Only specified Desktop Groups will be checked for restart

.EXAMPLE
	powershell.exe -ExecutionPolicy RemoteSigned -file <path to script> Nightly Server Reboots 7.x
.NOTES
	Run script from task scheduler
#> 


# Send mail
Function Send-Mail ($msgsubject, $msgbody){

	Write-Host "Sending Email"

	#SMTP server name
	$smtpServer = "SMTP.SERVER.ADDRESS"

	#Creating a Mail object
	$msg = new-object Net.Mail.MailMessage

	#Creating SMTP server object
	$smtp = new-object Net.Mail.SmtpClient($smtpServer)

	#Email structure 
	$msg.From = "DL.OR.EMAIL.TO.SEND.MAIL.FROM"
    $msg.To.Add("DL.OR.EMAIL.TO.SEND.MAIL.TO")
    $msg.ReplyTo = "DL.OR.EMAIL.TO.REPLY.TO"

	$msg.subject = $msgsubject
	$msg.IsBodyHTML = $true
	$msg.body = $msgbody 
	$smtp.Send($msg)
} #END Send-Mail

# Write log file
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
		[string]$Logfile = $MASTERLOG.FullName
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
} # END Write-Log

# Get a default search pattern depending on the day of the week
Function Get-SearchPattern {
    [CmdletBinding()]
    Param()
    BEGIN{ 
        $MATCHEVENPATTERN = "(\d+[02468])"
        $MATCHODDPATTERN = "(\d+[13579])"
        $DEFAULTSERVERSEARCHPATTERN = $MATCHEVENPATTERN
    }
    PROCESS{
        $today = [int](Get-Date).DayOfWeek
        Write-Log "Getting current day of week as an Integer"
        Write-Log "Today is: $today"

        if ($today % 2 -ne 0) {
            $DEFAULTSERVERSEARCHPATTERN = $MATCHODDPATTERN
        }
    }
    END{
        $logdefaultsearchpattern = if ($DEFAULTSERVERSEARCHPATTERN -eq $MATCHEVENPATTERN) {"EVEN NUMBER ENDING SERVER NAMES"} ELSE {"ODD NUMBER ENDING SERVER NAMES"}
        Write-Log "Setting default search pattern to: $logdefaultsearchpattern"
        return $DEFAULTSERVERSEARCHPATTERN
    }
} # END Get-SearchPattern

# Set restart time depending on the Delivery group tag
Function Set-RestartTime {
    [CmdletBinding()]
    Param($DeliveryGroupTag)
    BEGIN{
        Write-Log "Default Restart Schedule is: Daily"
        $dcTaglog = if ($DeliveryGroupTag -eq $null) {"Daily"} else {$DeliveryGroupTag}
        Write-Log "Delivery group tag is: $dcTaglog"
        $RESTARTTIME = 1 # Default (Restart Daily == 1)
    }
    PROCESS{
        if ($DeliveryGroupTag -eq $REBOOTSCHEDULE_EXCLUDE) {
            Write-Log "Restart Schedule is now: Exlcuded"
            $RESTARTTIME = 0
        } 
        elseif ($DeliveryGroupTag -eq $REBOOTSCHEDULE_WEEKLY) {
            Write-Log "Restart Schedule is now: Weekly"
            $RESTARTTIME = 7
        } 
    }
    END{
        return $RESTARTTIME # 0 == do not restart 1 == daily, 7 == weekly
    }
} # END Set-RestartTime

# Get Desktop groups after applying a filter
Function Filter-DesktopGroups {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory,HelpMessage="Filters separated by |")]
        [ValidateNotNullOrEmpty()]
        [string]$Filter,
        [Switch]$Only
    )
    BEGIN{}
    PROCESS{    
        if ($Only) {
            Write-Log "Filtering Delivery Groups matching: $Filter"
            $allDeliveryGroups = Get-BrokerDesktopGroup | where {($_.Name -match $Filter)}
        } Else {
            Write-Log "Filtering Delivery Groups NOT matching: $Filter"
            $allDeliveryGroups = Get-BrokerDesktopGroup | where {($_.Name -notmatch $Filter)} 
        }
        
    }
    END {
        Write-Log "Delivery groups returned: ->"
        foreach ($dc in $allDeliveryGroups) {Write-Log $dc.Name}
        return $allDeliveryGroups
    }
} # END Filter-DesktopGroups

# Get Server to be restarted in a Queue
Function Get-ServersToRestart {
    [CmdletBinding()]
    Param(
    [Parameter(Mandatory,HelpMessage="Filters separated by |")]
        [ValidateNotNullOrEmpty()]
        [string]$Filter = "maintenance|test|vdi",
        [Switch]$Only
    )
    BEGIN{
        # Get all delivery groups matching a custom filter
        Write-Log "Getting all delivery groups matching custom filter"
        if ($Only) {
            $allDeliveryGroups = Filter-DesktopGroups -Filter $Filter -Only
        } else {
            $allDeliveryGroups = Filter-DesktopGroups -Filter $Filter
        }
        
        
        Write-Log "Getting the deafult search pattern"
        $DEFAULTSERVERSEARCHPATTERN =  Get-SearchPattern

        $today = [int](Get-Date).DayOfWeek
    }
    PROCESS{
        Write-Log "Iterating through all Delivery Groups"
        foreach ($deliveryGroup in $allDeliveryGroups) {

            Write-Log "Processing $($deliveryGroup.Name)"
            # Get each deliver group custom tag property
            $RebootSchedule = Set-RestartTime -DeliveryGroupTag $deliveryGroup.Tags
            Write-Log "Delivery Group $($deliveryGroup.Name) reboot schedule is: $RebootSchedule"
    
            # get all servers in particular delivery group   
            $allServersInGroup = Get-BrokerMachine -SessionSupport MultiSession -DesktopGroupName $deliveryGroup.Name
            Write-Log "Multisession Servers in $($deliveryGroup.Name):"
            foreach ($srv in $allServersInGroup) {Write-Log "$($deliveryGroup.Name): $($srv.DnsName)"}
    
            foreach ($server in $allServersInGroup) {
                
                Write-Log "Processing $($server.DnsName)"

                # Get each server name, last 2/3 digits
                $serverName = ($server.DNSName -split "\.")[0]
                $serverNumber = [regex]::Matches($serverName, "(\d+)$").value

                # Create a custom object for each server
                $props = @{'DnsName'=$server.DNSName;
                           'InMaintenanceMode'=$server.InMaintenanceMode;
                           'PowerState'=$server.PowerState;
                           'DesktopGroupName'=$server.DesktopGroupName;
                           'ServerNumber'=$serverNumber;
                           'ServerName'=$serverName
                           'RebootSchedule'=$RebootSchedule}

                $log = (New-Log -LogFileName $serverName).FullName

                Write-Log "$serverName DnsName is: $($props.DnsName)" -Logfile $log
                Write-Log "$serverName ServerNumber is: $($props.ServerNumber)" -Logfile $log
                Write-Log "$serverName ServerName is: $($props.ServerName)" -Logfile $log
                Write-Log "$serverName InMaintenanceMode is: $($props.InMaintenanceMode)" -Logfile $log
                Write-Log "$serverName PowerState is: $($props.PowerState)" -Logfile $log
                Write-Log "$serverName DesktopGroupName is: $($props.DesktopGroupName)" -Logfile $log
                Write-Log "$serverName RebootSchedule is: $($props.RebootSchedule)" -Logfile $log

                $tempServer = New-Object -TypeName PSObject -Property $props

                # Check if the server is NOT in Maintenance Mode and IS Powered ON
                if (($tempServer.InMaintenanceMode -eq $false) -and ($tempServer.PowerState -eq "On")) {
                    Write-Log "$($tempServer.ServerName) Maintenance mode is: $($tempServer.InMaintenanceMode) and PowerState is: $($tempServer.PowerState)" -Logfile $log
                    Write-Log "$($tempServer.ServerName) Maintenance mode is: $($tempServer.InMaintenanceMode) and PowerState is: $($tempServer.PowerState)"
                    
                    # Check if servers has a RebootSchedule property of 1(Daily Reboot) AND its number matches the DefaultSearchpattern (looking for odd or even ending names depnding on the day of the week)
                    if (($tempServer.RebootSchedule -eq 1) -and ([regex]::Match($tempServer.DnsName, $DEFAULTSERVERSEARCHPATTERN).Success)) {
                        Write-Log "$($tempServer.ServerName) has Reboot Schedule set to: $($tempServer.RebootSchedule) (Daily Reboot) and is matching search pattern: $DEFAULTSERVERSEARCHPATTERN" -Logfile $log
                        Write-Log "$($tempServer.ServerName) scheduled for reboot" -Logfile $log
                        Write-Log "$($tempServer.ServerName) scheduled for reboot"
                        $targetServers.Enqueue($tempServer)
                    }
                    # Check if server has been excluded from reboots
                    elseif ($tempServer.RebootSchedule -eq 0) {
                        Write-Log "$($tempServer.ServerName) has Reboot Schedule set to: $($tempServer.RebootSchedule) (Excluded from Reboot)" -Logfile $log
                        Write-Log "$($tempServer.ServerName) has Reboot Schedule set to: $($tempServer.RebootSchedule) (Excluded from Reboot)"
                    }
                    # Check if server has a RebootSchedule property that is divisible by 7. If remainder EQUALS the day of the week. Server is tagged for reboot
                    elseif ([convert]::ToInt32($tempServer.ServerNumber, 10) % [convert]::ToInt32($tempServer.RebootSchedule, 10) -eq $today) {
                        Write-Log "$($tempServer.ServerName) has Reboot Schedule set to: $($tempServer.RebootSchedule) (Weekly Reboot)" -Logfile $log
                        Write-Log "$($tempServer.ServerName) scheduled for reboot" -Logfile $log
                        Write-Log "$($tempServer.ServerName) scheduled for reboot"
                        $targetServers.Enqueue($tempServer)
                    }
                    # If server does not match any of the queries DO NOTHING
                    else {
                        Write-Log "$($tempServer.ServerName) does not match the reboot pattern and will not be scheduled for reboot at this time" -Logfile $log
                        Write-Log "$($tempServer.ServerName) not scheduled for reboot"
                    } 
                }
                # Log only if server is Powered OFF or IN Maintenance Mode
                else {
                     Write-Log "$($tempServer.ServerName) Powered Off or in Maintencance Mode" -Logfile $log
                     Write-Log "$($tempServer.ServerName) Powered Off or in Maintencance Mode"
                }
            }  
        }
    }
    END{}
} #END  Get-ServersToRestart

# Sleep script until one hour before restart
Function Sleep-UntilTimeToRestart{
    [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
    Param()
    BEGIN{}
    PROCESS{
        # Wait until one hour before the restart time and before starting to reboot any machines
        # This is to allow time to drain sessions before users start receiving alerts
        $timeToSleep = ($RESTARTTIME.AddHours(-1) - $(Get-Date)).totalSeconds
        $ts =  [timespan]::fromseconds($timeToSleep)
        Write-Log "Sleeping for: $("{0:HH:mm:ss,fff}" -f ([datetime]$ts.Ticks))"
        Start-Sleep $timeToSleep
    }
    END{}
} # END Sleep-UntilTimeToRestart

# Set server connection status
Function Set-ConnectionStatus{
    [CmdletBinding()]
    [Parameter(Mandatory,HelpMessage="Connections status: QUERY ENABLE DISABLE DRAIN DRAINUNTILRESTART")]    
    Param([string]$ConnectionStatus,$Server,$log)
    BEGIN{}
    PROCESS{
        # SET ALL SESSIONS TO DRAINUNTILRESTART
        try {              
            Write-Log "Invoking $ConnectionStatus session on $Server" -Logfile $log
            Invoke-WmiMethod -ComputerName $Server -Path Win32_Process -Name create -ArgumentList "C:\Windows\System32\change.exe logon /$ConnectionStatus" -AsJob -ErrorAction Stop | Out-Null
        }
        Catch [Exception] {
            Write-Log "Cound not set $Server session to $ConnectionStatus, falling back ..." -Level WARN -Logfile $log
            if ($ConnectionStatus -eq "DRAINUNTILRESTART") {
                Write-Log "Trying to set $Server to Maintenance Mode"
                Set-BrokerMachine -MachineName $server.MachineName -InMaintenanceMode $true
            }
            else {
                Write-Log "Could not change $Server connection to $ConnectionStatus" -Level ERROR -Logfile $log
            }
        }
    }
    END{} 
} # END Set-DrainConnections

# Send Users a message
Function Send-UserMessage {
    [cmdletbinding()]
    Param([string]$Message,$Session, $log)
    BEGIN{}
    PROCESS{	
	    Write-Log "Seding $Message to all user sessions:"
        foreach ($s in $Session) {Write-Log "User: $($s.UserName)" -Logfile $log}
        Send-BrokerSessionMessage $Session -MessageStyle Information -Title "Reboot Warning" -Text $Message		
    }
    END{}
} # END Send-UserMessage


# Restart server with 0-5 min random delay
Function Restart-ServerWithDelay {
    [cmdletbinding()]
    [Parameter(Mandatory)]
    Param($Server,$log)
    BEGIN{

        # Randomize restart time (in minutes)
        $sleepFor = [int](Get-Random -Minimum 0 -Maximum 5) * 60
        Write-Log "Server restart dalyed by: $sleepFor seconds"
        Write-Log "Server restart dalyed by: $sleepFor seconds" -Logfile $log
    }
    PROCESS{
        $scriptBlock = {
            param($Server, $log, $sleepFor)
            Add-PSSnapin Citrix.*
            Start-Sleep -Seconds $sleepFor
            Write-Log "Sleep timer off. Restarting $Server" -Logfile $log
            New-BrokerHostingPowerAction -Action 'Restart' -MachineName $Server
            Write-Log "Waiting $Server for 2 minutes after reboot" -Logfile $log
            Start-Sleep -Seconds 120
            Write-Log "2 minutes wait timer off. Will Check server status" -Logfile $log
            Write-Log "Trying to set $Server out of Maintenance Mode"
            Set-BrokerMachine -MachineName "SHCSD\$Server" -InMaintenanceMode $false
        }
        Write-Log "Restart Job scheduled for $Server"
	    Start-Job -ScriptBlock $scriptBlock -Name $Server -InitializationScript $WRITELOGFUNC -ArgumentList $Server,$log,$sleepFor
    }
    END{
        return [string]$Server
    }
} # END Restart-ServerWithDelay

# Restar servers if no sessions or it is time to restart 
Function Restart-Servers {
    [CmdletBinding()]
    Param()
    BEGIN{}
    PROCESS{
        Write-Log "Processing all servers tagged for restart"

        foreach ($server in $targetServers) {
            Write-Log "Draining $($server.ServerName) sessions"
			Set-ConnectionStatus -ConnectionStatus "DRAINUNTILRESTART" -Server $server.ServerName -log $log
        }

        while ($targetServers.count -ne 0) {

           Write-Log "Server count is: $($targetServers.count)"
            
            $counter = $targetServers.Count

            for ($i = 0; $i -le $counter; $i++) {

                $timer = ($RESTARTTIME - (Get-Date)).TotalSeconds

                # get the current 
                $target = $targetServers.Dequeue()
                Write-Log "Processing $($target.ServerName)"

		        # generate log file        
                $log = New-Log -LogFileName $target.ServerName

                # get the sessions on each server
                $session = Get-BrokerSession -DNSName $target.DNSName 
                Write-Log "$($target.ServerName) has: $($session.Count) number of sessions" -Logfile $log
			
                if($timer -gt 0) {
                    Write-Log "$timer seconds left until restart" -Logfile $log
			        
                    if ($session.count -eq 0) {
                        Write-Log "Session's count on $($target.ServerName) is: $($session.Count)" -Logfile $log
                        
                        Write-Log "Initiating $($target.ServerName) restart" -Logfile $log
                        Restart-ServerWithDelay -Server $target.ServerName -log $log
                        
                        $rebootedServer.Push($target)
                        Write-Log "$($target.ServerName) removed from queue. Added to rebooting servers queue. Servers to reboot queue is now $($targetServers.Count)" -Logfile $log
			        }
			        else { # if there are still people logged in
                                                
                        # write user sessions to log file 
                        Write-Log "------------Sessions still on the server------------"  -Logfile $log
                        Write-Log "UserName: $($session.UserName)`t" -Logfile $log
                        Write-Log "UserFullName: $($session.UserFullName)`t" -Logfile $log
                        Write-Log "UserUPN: $($session.UserUPN)`t" -Logfile $log
                        Write-Log "SessionType: $($session.SessionType)`t" -Logfile $log
                        Write-Log "SessionState: $($session.SessionState)`t" -Logfile $log
                        Write-Log "EstablishmentTime: $($session.EstablishmentTime)`t" -Logfile $log
                        Write-Log "ApplicationsInUse: $($session.ApplicationsInUse)`t" -Logfile $log
                        Write-Log "Protocol: $($session.Protocol)`t" -Logfile $log
                        Write-Log "-----------------------------------------------------" -Logfile $log
                        
                        Write-Log "$($session.Count) sessions found on $($target.ServerName). Postponing reboot" -Logfile $log
                        
                        $targetServers.Enqueue($target)
                        [int]$countdown = $timer / 60
                        
                        Write-Log "$countdown minutes until reboot" -Logfile $log
                        
                        switch ($countdown) {
                            {50 .. 60 -contains $_} {
                                Send-UserMessage -Session $session -Message "The Citrix XenApp server ($($session.HostedMachineName)) you are using will be restarted in *$countdown minutes*. Please save your data and log off. Any unsaved data will be lost" -log $log
                                Write-Log "60 minute message sent to the user" -Logfile $log
                                break
                            } # if 60 minutes left
                            {21 .. 30 -contains $_} {
                                Send-UserMessage -Session $session -Message "The Citrix XenApp server ($($session.HostedMachineName)) you are using will be restarted in *$countdown minutes*. Please save your data and log off. Any unsaved data will be lost" -log $log
                                Write-Log "30 minute message sent to the user" -Logfile $log
                                break
                            } # if 30 minutes left
                            {11 .. 20 -contains $countdown} {
                                Send-UserMessage -Session $session -Message "The Citrix XenApp server ($($session.HostedMachineName)) you are using will be restarted in *$countdown minutes*. Please save your data and log off. Any unsaved data will be lost" -log $log
                                Write-Log "20 minute message sent to the user" -Logfile $log
                                break
                            } # if 20 minutes left
                            {6 .. 10 -contains $_} {
                                Send-UserMessage -Session $session -Message "The Citrix XenApp server ($($session.HostedMachineName)) you are using will be restarted in *$countdown minutes*. Please save your data and log off. Any unsaved data will be lost" -log $log
                                Write-Log "10 minute message sent to the user" -Logfile $log
                                break
                            } # if 10 minutes left
                            {1 .. 5 -contains $_} {
                                Send-UserMessage -Session $session -Message "The Citrix XenApp server ($($session.HostedMachineName)) you are using will be restarted in *$countdown minutes*. Please save your data and log off. Any unsaved data will be lost" -log $log
                                Write-Log "5 minute message sent to the user" -Logfile $log
                                break
                            } # if 5 minutes left
                        }   		
			        }
		        }
		        else { # if timer is 0 (time is up)
                    Write-Log "Timer is up. Rebooting $($target.ServerName) NOW" -Logfile $log
                    Write-Log "Draining $($target.ServerName) sessions" -Logfile $log
                    Send-UserMessage -Session $session -Message "The Citrix XenApp server ($($session.HostedMachineName)) you are using will be restarted in *$countdown minutes*. Please save your data and log off. Any unsaved data will be lost" -log $log
                    Write-Log "Final message sent to the user" -Logfile $log
                    Set-ConnectionStatus -ConnectionStatus "DRAINUNTILRESTART" -Server $target.ServerName -log $log
                    Start-Sleep -Seconds 30
                    Restart-ServerWithDelay -Server $target.ServerName -log $log
                    
                    $rebootedServer.Push($target)
                    Write-Log "$($target.ServerName) removed from queue. Added to rebooting servers queue. Servers to reboot queue is now $($targetServers.Count)" -Logfile $log
		        }
            }

	        if($timer -gt 0) { # sleep for 5 minutes
		        if($targetServers.count -ne 0) {
			        $timer -= 300
    			    Write-Log "Seelping for 5 minutes"  
                    Write-Log "Seelping for 5 minutes" -Logfile $log
                    Start-Sleep 300
		        }
	        }
        }
    }
    END{
        # Wait for all restart jobs
        Write-Log "Waiting for reboot jobs to complete. Timeout is 240 seconds"
        Get-Job | Wait-Job -Timeout 240
        
        # Check all rebooted server status
        Write-Log "Checking server status health after reboot"
        Get-ServerHealth -log $log
    }
} # END  Restart-Servers
 
 # Set Log folder structure and generate log file
 Function New-Log{
    [cmdletbinding()]
    Param($LogFileName = "temp")
    BEGIN {
        $FULLLOGPATH = "$LOGPARENTDIR\$YEAR\$MONTH\$DAY\$LogFileName.log"
    }
    PROCESS{
        try {
            if (!(Test-Path $FULLLOGPATH)) {
                New-Item -ItemType File -Path $FULLLOGPATH -Force -ErrorAction Stop
                #Write-Log "Created: $FULLLOGPATH"
            }
        }
        catch [Exception] {
            Write-Log "Could not create log file: `'$FULLLOGPATH`'"
        }
    }
    END {
        return $FULLLOGPATH
    }
 } #END New-Log

 # Get service status
 Function Get-ServiceStatus {
    [cmdletbinding()]
    Param($Service = "Citrix*", $Server, $log)

    BEGIN{
        Write-Log "Getting all services matching $Service query on $Server" -Logfile $log
        $CitrixServices = Get-WmiObject -Class win32_service -ComputerName $Server | Where-Object {$_.Name -match $Service} | Select-Object Name,State,Status
        [boolean]$needsAttention = $true
    }
    PROCESS{
        foreach ($svc in $CitrixServices) {
            if ($svc.State -ne "Running" -or $svc.Status -ne "OK") {
                Write-Log "$($svc.Name) is in a $($svc.State) state and has a $($svc.Status) status" -Level ERROR -Logfile $log
                $needsAttention = $false
            } else {
                 Write-Log "$($svc.Name) is in a $($svc.State) state and has a $($svc.Status) status" -Logfile $log
            }
        }
    
        if (!($needsAttention)) {
            Write-Log "Server $Server needs your attention" -Level WARN -Logfile $log
        }
        else {
            Write-Log "Server $Server status after reboot:  Healthy" -Logfile $log
        }
    }
    END{}
 } # END Get-ServiceStatus

 # Get Server Health
 Function Get-ServerHealth {
    [cmdletbinding()]
    Param($log)

    BEGIN{}
    PROCESS{
        While ($rebootedServer.Count -gt 0) {
            $Server = $rebootedServer.Pop()

            $log = $log.Substring(0, $log.LastIndexOf("\"))
            $log += "\$($Server.ServerName).log"
            Write-Log "Getting $($Server.ServerName) health status" -Logfile $log
            Get-ServiceStatus -Server $Server.ServerName -log $log       
        }
    }
    END{}
 }

 # Get Current Functio Name
 Function Get-FunctionName { 
    (Get-Variable MyInvocation -Scope 1).Value.MyCommand.Name;
} # END Get-FunctionName


 # Load Citrix specifc modules
Add-PSSnapin Citrix.*

#region Declare variables and Constants

# Declare the log function as a script block. To be used later in the Start-Job
$WRITELOGFUNC = {
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
		    [string]$Logfile = $MASTERLOG.FullName
	    )
        BEGIN {
    	    $Stamp = (Get-Date).toString("yyyy/MM/dd HH:mm:ss")
	        $Line = "$Stamp $Level $Message`r`n"
        }
        PROCESS {
    	    If ($Logfile) {
                [System.IO.File]::AppendAllText($Logfile, $Line)
	        } Else {
		        # Write-Output $Line
	        }
        }
        END {}
    } # END Write-Log
}


$targetServers =[System.Collections.Queue]::Synchronized((New-Object System.Collections.Queue)) # will hold all servers that are going to be restarted
$rebootedServer = [System.Collections.Stack]::Synchronized((New-Object System.Collections.Stack)) # will hold all servers that have been restarted already

# get current year, date, month etc.; used in various places throughout the scritp and log file folder structure
$DATE = Get-Date
$YEAR = $DATE.Year
$MONTH = $DATE.Month
$DAY = $DATE.Day

# set restart time
$delay = (24 - $DATE.Hour) + 3
$RESTARTTIME = $DATE.AddDays(0).AddHours($delay).AddMinutes(0)

# set restart constants
$REBOOTSCHEDULE_EXCLUDE= "Reboot Schedule Excluded" # 0
$REBOOTSCHEDULE_WEEKLY = "Reboot Schedule Weekly" # 7

# Set log file location
$LOGPARENTDIR = "\\UNC\PATH\WHERE\LOGS\WILL\BE\SAVED"

$MASTERLOG = New-Log -LogFileName "Master"
#endregion


Get-ServersToRestart -Filter "DELIVER GROUP NAME" -Only

Sleep-UntilTimeToRestart


# Timer (in seconds), representing the amount of time until servers can restart 
$timer = ($RESTARTTIME - (Get-Date)).TotalSeconds

Restart-Servers