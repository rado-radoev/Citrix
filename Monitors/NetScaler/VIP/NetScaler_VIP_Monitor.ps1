#region constants
$CONTENTTYPE = "application/json"
$NS = "NETSCALER_IP_ADDRESS"
$CONFIGURI = "http://$NS/nitro/v1/config"
$STATURI = "http://$NS/nitro/v1/stat"
#endregion

#region authentication stuff

$password = (Get-Content "C:\Scripts\ns.creds")[1].ToString()
$user = (Get-Content "C:\Scripts\ns.creds")[0].ToString()
<#
$CREDS = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $user, $password

$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($password)
$UnsecurePassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)

$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($user)
$UnsecureUser = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
#endregion
#>
#region authenticate and login
$LoginJSON = @{"login" = @{"username"=$user;"password"=$password;"timeout"=”360”}} | ConvertTo-Json
$LoginREST = Invoke-RestMethod -Uri "$configURI/login" -Body $LoginJSON -Method POST -SessionVariable NetScalerSession -ContentType $ContentType

#endregion

#region vips of interest
# Add monitor names to array. Some example monitornames below
$vips = New-Object System.Collections.ArrayList
$vips.add("VIP_internal_StoreFront") | out-null
$vips.add("VIP_XML") | out-null
$vips.add("VIP_tftp") | out-null
$vips.add("VIP_DeliveryControllers") | out-null
#endregion

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


#region HTML body formatter
$head = @'
<Title>Netscaler VIP Status</Title>
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

$vipsStatus = New-Object System.Collections.ArrayList

#get ip add, server name, port, state for each server
$serverMembers = New-Object System.Collections.ArrayList

foreach ($vip in $vips) 
{
    $tempVip = New-Object -TypeName psobject
    # Get VIP info
    $temp = Invoke-RestMethod -Uri "$CONFIGURI/lbvserver/$vip" -ContentType $CONTENTTYPE -WebSession $NetScalerSession
    
    $tempVip | Add-Member -MemberType NoteProperty -Name "Name" -Value $($temp.lbvserver | select -ExpandProperty name)
    $tempVip | Add-Member -MemberType NoteProperty -Name "IP" -Value $($temp.lbvserver | select -ExpandProperty ipv46)
    $tempVip | Add-Member -MemberType NoteProperty -Name "Port" -Value $($temp.lbvserver | select -ExpandProperty port)
    $tempVip | Add-Member -MemberType NoteProperty -Name "ServiceType" -Value $($temp.lbvserver | select -ExpandProperty servicetype)
    $tempVip | Add-Member -MemberType NoteProperty -Name "CurrentState" -Value $($temp.lbvserver | select -ExpandProperty curstate)
    $tempVip | Add-Member -MemberType NoteProperty -Name "EffectiveState" -Value $($temp.lbvserver | select -ExpandProperty effectivestate)
    $tempVip | Add-Member -MemberType NoteProperty -Name "TotalServices" -Value $($temp.lbvserver | select -ExpandProperty totalservices)
    $tempVip | Add-Member -MemberType NoteProperty -Name "ActiveServices" -Value $($temp.lbvserver | select -ExpandProperty activeservices)
    $tempVip | Add-Member -MemberType NoteProperty -Name "Health" -Value $($temp.lbvserver | select -ExpandProperty health)

    # Get service group name
    $temp2 = Invoke-RestMethod -Uri "$CONFIGURI/lbvserver_servicegroup_binding/$vip" -ContentType $CONTENTTYPE -WebSession $NetScalerSession

    $tempVip | Add-Member -MemberType NoteProperty -Name "ServiceGroupName" -Value $($temp2.lbvserver_servicegroup_binding | select -ExpandProperty ServiceGroupName)

    # Get the servers that are being monitored
	#http://$NS/nitro/v1/config/servicegroup_servicegroupmember_binding/sg_internal_storefront
	$serviceGroupName = $temp2.lbvserver_servicegroup_binding | select -ExpandProperty servicegroupname
	
	$serviceGroupMemberBinding = Invoke-RestMethod -Uri "$CONFIGURI/servicegroup_servicegroupmember_binding/$serviceGroupName" -ContentType $CONTENTTYPE -WebSession $NetScalerSession
	
	foreach ($srvMember in $serviceGroupMemberBinding.servicegroup_servicegroupmember_binding) {
		$tempSrvMbr = New-Object -TypeName psobject
		
		$tempSrvMbr | Add-Member -MemberType NoteProperty -Name "IP" -Value $($srvMember | select -ExpandProperty ip)
		$tempSrvMbr | Add-Member -MemberType NoteProperty -Name "Port" -Value $($srvMember | select -ExpandProperty port)
		$tempSrvMbr | Add-Member -MemberType NoteProperty -Name "State" -Value $($srvMember | select -ExpandProperty state)
		$tempSrvMbr | Add-Member -MemberType NoteProperty -Name "SGName" -Value $($srvMember | select -ExpandProperty servicegroupname)
		$tempSrvMbr | Add-Member -MemberType NoteProperty -Name "ServerName" -Value $($srvMember | select -ExpandProperty servername)
		$tempSrvMbr | Add-Member -MemberType NoteProperty -Name "ServerState" -Value $($srvMember | select -ExpandProperty svrstate)
		
		# read all the monitors and display status and last response
		$srvMemmberMonitorDetails = Invoke-RestMethod -Uri "$CONFIGURI/servicegroup_servicegroupentitymonbindings_binding/$($serviceGroupName)?filter=servicegroupentname2:$($serviceGroupName)?$($tempSrvMbr.ServerName)?$($tempSrvMbr.Port)&pageno=1&pagesize=25" -ContentType $CONTENTTYPE -WebSession $NetScalerSession
		
		$monCount = 0
		foreach ($monitor in $srvMemmberMonitorDetails.servicegroup_servicegroupentitymonbindings_binding)
		{
			$monCount++
			$tempSrvMbr | Add-Member -MemberType NoteProperty -Name "MonitorName$($monCount)" -Value $($monitor | select -ExpandProperty monitor_name)
			$tempSrvMbr | Add-Member -MemberType NoteProperty -Name "MonitorState$($monCount)" -Value $($monitor | select -ExpandProperty monitor_state)
			$tempSrvMbr | Add-Member -MemberType NoteProperty -Name "LastResponse$($monCount)" -Value $($monitor | select -ExpandProperty lastresponse)
		}
		
		$serverMembers.Add($tempSrvMbr)
	}

    $vipsStatus.Add($tempVip) | Out-Null
    $tempVip = $null
}

# Logout from NetScaler
$logoutJSON = @{"logout" = @{}} | ConvertTo-Json
$logoutREST = Invoke-RestMethod -Uri "$CONFIGURI/logout" -Method Post -Body $logoutJSON -ContentType $CONTENTTYPE -WebSession $NetScalerSession


foreach ($vip in $vipsStatus)
{   
    $name = $vip | select -ExpandProperty name
    $curState = $vip | select -ExpandProperty CurrentState
    $effectiveState = $vip | select -ExpandProperty EffectiveState
    $health = $vip | select -ExpandProperty health

    # get vip SG. If it matches any of the $serverMembers service groups add them to the html body
	$vipSG = $vip.ServiceGroupName
	
	$tempMon = New-Object System.Collections.ArrayList
	foreach ($i in $serverMembers) {
		if ($i.SGName -eq $vipSG) {
			$tempMon.Add($i)
		}
	}

    $htmlBody = ConvertTo-Html -Head $head -Body (($vip | select name, IP, port, servicetype, CurrentState, effectivestate, totalservices, activeservices, health, ServiceGroupName | ConvertTo-Html -Fragment) + "<br>" + '<p style="margin-left: 3.5em"> Monitor Details:</p>' + ($tempMon | ConvertTo-Html -Head $head -As List))
	
    if ($curState -ne "UP") 
    {
        Send-Mail -msgsubject "Netscaler VIP - $name Current state: $curState" -msgbody "$name Current state: $curState" -pageEDA
        Send-Mail -msgsubject "Netscaler VIP - $name Current state: $curState" -msgbody $htmlBody
    }
    elseif ($effectiveState -ne "UP") 
    {
        Send-Mail -msgsubject "$name Effective state: $effectiveState" -msgbody $htmlBody
    }
    elseif ([int]$health -lt 100)
    {
        Send-Mail -msgsubject "$name Health at: $health%" -msgbody $htmlBody
    }
    elseif ([int]$health -eq 0)
    {
        Send-Mail -msgsubject "Netscaler VIP - $name Health at: $health%" -msgbody "$name Health at: $health%" -pageEDA
        Send-Mail -msgsubject "$name Health at: $health%" -msgbody $htmlBody
    }


    #$vip | select name,IP,port,servicetype,CurrentState,effectivestate,totalservices,activeservices,health,ServiceGroupName
}