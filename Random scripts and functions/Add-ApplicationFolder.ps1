Import-Module "C:\Program Files\Citrix\Provisioning Services Console\Citrix.PVS.SnapIn.dll"
if (-not (Get-PSSnapin | where {$_.Name -Like "*Citrix*"})) {
    Add-PSSnapin Citrix*
}


Function Add-ApplicationFolder{
    [CmdletBinding()]
    Param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    #[ValidatePattern("PREFIX_(OTHER|PATTERN|HERE)[aA-zZ]{3,4}CTX\d+")]
    [string]$ApplicationFolder,

    [Parameter(Mandatory)]
    [alias("DeliveryController")]
    [ValidateSet('DC1','DC2','DC3', 'DC4')] # Making sure the correct DC is used
    [ValidateNotNullOrEmpty()]
    [string]$DC
    )
    BEGIN{
        $logs = Start-LogHighLevelOperation  -AdminAddress $DC -Source "Studio" -StartTime (Get-Date).ToString() -Text "Creating application folder `'$ApplicationFolder`'"
        Write-Verbose "Creating log in Studio with ID: $($logs.Id)"
    }
    PROCESS{
        $ExistingApplicationFolder = $null
        TRY {
            $ExistingApplicationFolder = Get-BrokerAdminFolder -Name $ApplicationFolder -ErrorAction Stop
        } catch {
            $ExistingApplicationFolder = New-BrokerAdminFolder -AdminAddress $DC -FolderName $ApplicationFolder -LoggingId $logs.Id
        }
    }
    END{
        Stop-LogHighLevelOperation  -AdminAddress $DC -EndTime (Get-Date).ToString() -HighLevelOperationId $logs.Id -IsSuccessful $True
        Write-Verbose "Stopped logging in Studio. ID: $($logs.Id)"
    }
}

Add-ApplicationFolder -ApplicationFolder "XENAPP_APPLICATION_FOLDER_1" -DC prsmctxdc1 -Verbose