Add-PSSnapin Citrix.*

# Global variable controlling the uptime 
$MAXUPTIME = -[Math]::Abs(3)

# Global variable containing a list of servers to exclude
# Add servers (one per row) that need to be excluded from the query
$EXCLUSIONSLIST = New-Object System.Collections.ArrayList
$EXLUSIONSFILE = "C:\Scripts\DetectBootTimeExclude.txt"
$EXCLUSIONSLIST.AddRange($(Get-Content $EXLUSIONSFILE))

# HTML body formatter
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

# Send mail
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
	$msg.From = "EMAIL.ADD.OR.DL.SENDING.EMAIL"
	
    $msg.To.Add("RECEPIENT.DL.OR.EMAIL")
    $msg.ReplyTo = "REPLY.TO.DL.OR.EMAIL"
	$msg.subject = $msgsubject
	$msg.IsBodyHTML = $true
	$msg.body = $msgbody 
	$smtp.Send($msg)
} #END Send-Mail


$machines = Get-BrokerMachine -AdminAddress socxd78ddc01 -MaxRecordCount 10000 -SessionSupport MultiSession
$listOfBadServers = New-Object System.Collections.ArrayList

foreach ($machine in $machines) 
{

    if ($machine.HostedMachineName -ne $null `
        -and $machine.PowerState -ne "PoweredOn" `
        -and (!($EXCLUSIONSLIST.Contains($machine.HostedMachineName.ToString()))) `
        -and (Test-Connection -ComputerName $machine.HostedMachineName -BufferSize 16 -TimeToLive 3 -Count 2 -Quiet))
    {
        $badServerDetails = New-Object -TypeName psobject

        try 
        {
            $os = Get-WmiObject win32_operatingsystem -ComputerName $machine.HostedMachineName -ErrorAction Stop
            $bootTime = $os.ConvertToDateTime($os.LastBootUpTime)
            $timeSpan = New-TimeSpan -End $bootTime

            if ($timeSpan.Days -le $MAXUPTIME)
            {
                #Write-Host "$($machine.HostedMachineName) rebooted $([Math]::Abs($timeSpan.Days)) days ago" -ForegroundColor Yellow
                $badServerDetails | Add-Member -MemberType NoteProperty -Name "Server" -Value $machine.HostedMachineName
                $badServerDetails | Add-Member -MemberType NoteProperty -Name "UpTime" -Value "$([Math]::Abs($timeSpan.Days))"
                $listOfBadServers.Add($badServerDetails) | Out-Null

            }
        }
        Catch 
        {
            # NO IMPLEMENTATION 
        }
        Finally 
        {
            $badServerDetails = $null
        }
    }

}

if ($listOfBadServers.Count -gt 0) {
    $htmlBody = ConvertTo-Html -Head $head -Body $($listOfBadServers | 
                                                    select Server, @{Name="UpTime (Days)"; Expression={$_.UpTime}} | 
                                                    Sort-Object Server, UpTime -Descending | 
                                                    ConvertTo-Html -Fragment)

    Send-Mail -msgsubject "Citrix servers uptime > $([Math]::Abs($MAXUPTIME)) days" -msgbody $htmlBody
}