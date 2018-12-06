$VerbosePreferenceOld = $VerbosePreference
$VerbosePreference = "Continue"



<#

	This script is usually run as a scheduled task on a StoreFront server or a server
	that has access to the storefront servers. It should be using an account that has 
	at least access to read the event logs. It could be set up to run either on event
	or every X minutes to check the event logs for specific event IDs and fire an e-mail
	alert if X event entries are detected in X amount of minutes.

#>

#region Send-mail
Function Send-Mail{
    [CmdletBinding()]
    Param (
		[Parameter(Mandatory)]
		$msgsubject,
		[Parameter(Mandatory)]
		$msgbody,
	)

	#SMTP server name
	$smtpServer = "YOUR.SMPT.SERVER.HERE"

	#Creating a Mail object
	$msg = new-object Net.Mail.MailMessage

	#Creating SMTP server object
	$smtp = new-object Net.Mail.SmtpClient($smtpServer)

	#Email structure    
    $msg.From = "SERVICE.EMAIL.THAT.SENDS.EMAILS"
    $msg.To.Add("DL.OR.USER.TO.SEND.MAIL.TO")
    $msg.ReplyTo = "DL.OR.USER.TO.REPLY.TO"
	
    $msg.subject = $msgsubject
	$msg.IsBodyHTML = $true
	$msg.body = $msgbody 
	$smtp.Send($msg)
} 
#endregion Send-Mail

#region HTML-Head
$head = @'
<Title>Server Uptime</Title>
<style>
body 
{ 
 background-color:#FFFFFF;
 font-family:Tahoma;
 font-size:12pt; 
}
td, th 
{ 
 border:1px solid black; 
 border-collapse:collapse; 
}
th 
{
 color:white;
 background-color:black; 
}
table, tr, td, th { padding: 5px; margin: 0px }
table { margin-left:50px; }
</style>
'@
#endregion

#region StoreFront Servers
$StoreFrontServers = @("STOREFRONT.SERVER.1", "STOREFRONT.SERVER.2") # List of StoreFront Server
#endregion

#region Constants
$MAXCOUNT = 15
$TIMEPERIOD = 5
$LOGNAME = "Citrix Delivery Services"
$SOURCE = "Citrix Store Service"
#endregion

$Events = New-Object System.Collections.ArrayList

# Loop through the storefront servers and check the event log for specific events
foreach ($server in $StoreFrontServers) 
{
    $Events4012 = Get-EventLog -ComputerName $server -LogName $LOGNAME -InstanceId 4012 -EntryType Error -Source $SOURCE -Newest $MAXCOUNT -ErrorAction SilentlyContinue
    $Events4003 = Get-EventLog -ComputerName $server -LogName $LOGNAME -InstanceId 4003 -EntryType Error -Source $SOURCE -Newest $MAXCOUNT -ErrorAction SilentlyContinue
    $Events0 = Get-EventLog -ComputerName $server -LogName $LOGNAME -InstanceId 0 -EntryType Error -Source $SOURCE -Newest $MAXCOUNT -ErrorAction SilentlyContinue

    # If no events are registered, there is nothing to add to the array
    if ($Events4012) { $Events.Add($Events4012) | Out-Null } else { Write-Verbose ("No events for eventId: 4012 on $server") }
    if ($Events4003) { $Events.Add($Events4003) | Out-Null } else { Write-Verbose ("No events for eventId: 4003 on $server") }
    if ($Events0) { $Events.Add($Events0) | Out-Null } else { Write-Verbose ("No events for eventId: 0 on $server") }

    if ($Events.Count -gt 0) {
        foreach ($EventId in $Events) 
        {
            if ($EventID.Count -ge $MAXCOUNT)
            {
                # Check the oldest event timestamp and compare it against the current time -X minutes
                # if last event has occured in -X minutes send mail/page
                # else nothing to report
                $LastEventTimeGenerated  = ($EventId[$EventId.Count - 1]).TimeGenerated
                if ($LastEventTimeGenerated -le (Get-Date) -and (!($LastEventTimeGenerated -le (Get-Date).AddMinutes(-$TIMEPERIOD))))
                {
                    Write-Verbose ("Something bad happened on $server")
                    $msgBody = "Event {0} occured on {1} more then {2} times in a period of {3} minutes.`r`n Last Event message: {4}`r`nLast Event time: {5}" -f $EventId[0].InstanceId, $server, $MAXCOUNT, $TIMEPERIOD, $EventId[0].Message, $EventId[0].TimeGenerated
                    Send-Mail -msgsubject "External Storefront $server ON FIRE" -msgbody $msgBody
                } 
                else 
                {
                    Write-Verbose ("Life is good. Nothing to report on $server")
                    Write-Verbose ("No abnormal events count for: $($EventId[0].InstanceId) on $server")
                }
            } 
        }
    }

    # Clear array contents for the next storefront to write data
    Write-Verbose ("----------")
    $Events.Clear()
}

$VerbosePreference = $VerbosePreferenceOld
