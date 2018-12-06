<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2018 v5.5.152
	 Created on:   	8/30/2018 16:19 PM
	 Created by:   	superklamer
	 Organization: 	GitHub
     Filename:     	Netscaler_SX_Monitor.ps1
	===========================================================================
	.DESCRIPTION
        This script will be monitoring the health status of the Netscaler SDX instance
        It monitors Fan Speed, Power supply status, temperature details, disk status and summary details
        In case failure is detected an e-mail alert is sent to an e-mail address or distribution list.

        This script can be run as scheduled task 
#>

#region constants
$CONTENTTYPE = "application/json"
$SDX_INST1 = "SDX_INST1" # use either IP or HOSTNAME
$SDX_INST2 = "127.0.0.1"
$SDX_INST3 = "127.0.0.1"
$CONFIGURI = "http://$SDX_PHX/nitro/v1/config"
$STATURI = "http://$SDX_PHX/nitro/v1/stat"
#endregion

#region authentication stuff
# Password and username are stored as a secure string in a separate file 
$password = (Get-Content "C:\Scripts\sdx.creds")[1] | ConvertTo-SecureString  
$CREDS = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $user, $password

$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($password)
$UnsecurePassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)

$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($user)
$UnsecureUser = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
#endregion

#region authenticate and login
<#
$LoginJSON = ConvertTo-Json @{
                    "object" = @{
                        "login" = @{ 
                                    "username" = $UnsecureUser; 
                                    "password" = $UnsecurePassword
                                   } 
                   
                                }
                            }
#>

$LoginJSON = 'object= { "login": { "username":"nsroot", "password":"Alp5ie" }}'

$LoginREST = Invoke-RestMethod -Uri "$configURI/login" -Body $LoginJSON -Method POST -SessionVariable NetScalerSession -ContentType $CONTENTTYPE
#endregion

#region Send mail
Function Send-Mail
{
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
}
#endregion Send-Mail

#region HTML body formatter
$head = @'
<Title>SDX Health Status</Title>
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


$powerSupplyDetails = New-Object -TypeName Psobject
$fanDetails = New-Object -TypeName Psobject
$tempDetails = New-Object -TypeName Psobject
$diskDetails = New-Object -TypeName Psobject
$summaryDetails = New-Object -TypeName Psobject
[boolean]$needsAttention = $False

$msgBody = $null

# capture power monitor details
$powerRequest = Invoke-RestMethod -Uri "$CONFIGURI/xen_health_monitor_misc" -ContentType $CONTENTTYPE -WebSession $NetScalerSession

$psuCount = 1
foreach ($psu in $powerRequest.xen_health_monitor_misc)
{
	$powerSupplyDetails | Add-Member -MemberType NoteProperty -Name "PSU$psuCount" -Value $psu.name
	$powerSupplyDetails | Add-Member -MemberType NoteProperty -Name "PSU$($psuCount)_Status" -Value $psu.status
	$powerSupplyDetails | Add-Member -MemberType NoteProperty -Name "PSU$($psuCount)_Failures" -Value $psu.number_of_failures
	
	$psuCount++
	
	if ($psu.number_of_failures -gt 0)
	{
		$needsAttention = $True
		$msgBody = $powerSupplyDetails
	}
}

#capture fan details
$fanRequest = Invoke-RestMethod -Uri "$CONFIGURI/xen_health_monitor_fan_speed" -ContentType $CONTENTTYPE -WebSession $NetScalerSession
$fanNumber = 1
foreach ($fan in $fanRequest.xen_health_monitor_fan_speed)
{
	if ($fan.current_value -ne "-NA-")
	{
		$fanDetails | Add-Member -MemberType NoteProperty -Name "Fan$($fanNumber)" -Value $fan.name
		$fanDetails | Add-Member -MemberType NoteProperty -Name "Fan$($fanNumber)_Status" -Value $fan.status
		$fanDetails | Add-Member -MemberType NoteProperty -Name "Fan$($fanNumber)_Failures" -Value $fan.number_of_failures
		$fanDetails | Add-Member -MemberType NoteProperty -Name "Fan$($fanNumber)_RMP" -Value $fan.current_value
		
		if ($fan.status -ne "OK")
		{
			$needsAttention = $True
			$msgBody = $fanDetails
		}
	}
	$fanNumber++
}

# capture disk details
$diskRequest = Invoke-RestMethod -Uri "$CONFIGURI/xen_health_sr" -ContentType $CONTENTTYPE -WebSession $NetScalerSession
$diskNumber = 1

foreach ($disk in $diskRequest.xen_health_sr)
{
	$diskDetails | Add-Member -MemberType NoteProperty -Name "Disk$($diskNumber)_Name" -Value $disk.name
	$diskDetails | Add-Member -MemberType NoteProperty -Name "Disk$($diskNumber)_BayNumber" -Value $disk.bay_number
	$diskDetails | Add-Member -MemberType NoteProperty -Name "Disk$($diskNumber)_Status" -Value $disk.status
	$diskDetails | Add-Member -MemberType NoteProperty -Name "Disk$($diskNumber)_Size" -Value $('{0:f2}' -f $($disk.size/1GB))
	$diskDetails | Add-Member -MemberType NoteProperty -Name "Disk$($diskNumber)_Utilized" -Value $('{0:f2}' -f $($disk.utilized/1GB))
	$diskDetails | Add-Member -MemberType NoteProperty -Name "Disk$($diskNumber)_FreePercent" -Value $(($($disk.size - $disk.utilized) / $disk.size).ToString("P"))
	
	$diskNumber++
	
	if (($disk.status -ne "GOOD") -or ((($($disk.size - $disk.utilized) / $disk.size) * 100) -lt 10))
	{
		$needsAttention = $True
		$msgBody = $diskDetails
	}
	
}


# capture temp details
$tempRequest = Invoke-RestMethod -Uri "$CONFIGURI/xen_health_monitor_temp" -ContentType $CONTENTTYPE -WebSession $NetScalerSession
$tempCount = 1


foreach ($item in $tempRequest.xen_health_monitor_temp)
{
	$tempDetails | Add-Member -MemberType NoteProperty -Name "Unit$($tempCount)" -Value $item.name
	$tempDetails | Add-Member -MemberType NoteProperty -Name "Unit$($tempCount)_Status" -Value $item.status
	$tempDetails | Add-Member -MemberType NoteProperty -Name "Unit$($tempCount)_CurrentValue" -Value $item.current_value
	$tempDetails | Add-Member -MemberType NoteProperty -Name "Unit$($tempCount)_NumberOfFailures" -Value $item.number_of_failures
	
	$tempCount++
	
	if ($item.status -ne "OK")
	{
		$needsAttention = $True
		$msgBody = $tempDetails
	}
}

# capture summary details
$summaryRequest = Invoke-RestMethod -Uri "$CONFIGURI/xen_health_summary" -ContentType $CONTENTTYPE -WebSession $NetScalerSession

$summaryDetails | Add-Member -MemberType NoteProperty -Name "Last_poll_time_resources" -Value $summaryRequest.xen_health_summary.last_poll_time_resources
$summaryDetails | Add-Member -MemberType NoteProperty -Name "Last_poll_time_sensors" -Value $summaryRequest.xen_health_summary.last_poll_time_sensors
$summaryDetails | Add-Member -MemberType NoteProperty -Name "sensor_temp" -Value $summaryRequest.xen_health_summary.sensor_temp
$summaryDetails | Add-Member -MemberType NoteProperty -Name "storage_disk" -Value $summaryRequest.xen_health_summary.storage_disk
$summaryDetails | Add-Member -MemberType NoteProperty -Name "sensor_volt" -Value $summaryRequest.xen_health_summary.sensor_volt
$summaryDetails | Add-Member -MemberType NoteProperty -Name "resource_sw" -Value $summaryRequest.xen_health_summary.resource_sw
$summaryDetails | Add-Member -MemberType NoteProperty -Name "resource_hw" -Value $summaryRequest.xen_health_summary.resource_hw
$summaryDetails | Add-Member -MemberType NoteProperty -Name "sensor_misc" -Value $summaryRequest.xen_health_summary.sensor_misc
$summaryDetails | Add-Member -MemberType NoteProperty -Name "storage_repo" -Value $summaryRequest.xen_health_summary.storage_repo
$summaryDetails | Add-Member -MemberType NoteProperty -Name "sensor_fan" -Value $summaryRequest.xen_health_summary.sensor_fan

<#
$htmlbody = ConvertTo-Html -Head $head -Body (
        '<p style="margin-left: 3.5em"> PSU Details:</p>' + 
        ($powerSupplyDetails | ConvertTo-Html -Fragment -As List) + 
        '<p style="margin-left: 3.5em"> Fan Details:</p>' + 
        ($fanDetails | ConvertTo-Html -Fragment -As List) + 
        '<p style="margin-left: 3.5em"> Temp Details:</p>' + 
        ($tempDetails | ConvertTo-Html -Fragment -As List) +
        '<p style="margin-left: 3.5em"> Disk Details:</p>' + 
        ($diskDetails | ConvertTo-Html -Fragment -As List) +
        '<p style="margin-left: 3.5em"> Summary:</p>' + 
        ($summaryDetails | ConvertTo-Html -Fragment -As List) )
#>

if ($needsAttention)
{
	$htmlbody = ConvertTo-Html -Head $head -Body (
		'<h1><p style="margin-left: 1.5em; color:red"> <strong> Failing Component</p></h1>' +
		($msgBody | ConvertTo-Html -Fragment -As List) +
		'<p style="margin-left: 3.5em"> Summary Details:</p>' +
		($summaryDetails | ConvertTo-Html -Fragment -As List))
	
	Send-Mail -msgsubject "SDX $SDX_PHX Health Status Report" -msgbody $htmlbody
}

# Logout from NetScaler
$logoutJSON = 'object= { "logout": { }}'
$logoutREST = Invoke-RestMethod -Uri "$CONFIGURI/logout" -Method Post -Body $logoutJSON -ContentType $CONTENTTYPE -WebSession $NetScalerSession