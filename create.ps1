#####################################################
# HelloID-Conn-Prov-Target-AFAS-Profit-Employees-Create
#
# Version: 3.0.0 | new-powershell-connector
#####################################################

# Set to true at start, because only when an error occurs it is set to false
$outputContext.Success = $true

# AccountReference must have a value for dryRun
$outputContext.AccountReference = "Unknown"

# Set debug logging
switch ($($actionContext.Configuration.isDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

#region functions
function Resolve-HTTPError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory,
            ValueFromPipeline
        )]
        [object]$ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            FullyQualifiedErrorId = $ErrorObject.FullyQualifiedErrorId
            MyCommand             = $ErrorObject.InvocationInfo.MyCommand
            RequestUri            = $ErrorObject.TargetObject.RequestUri
            ScriptStackTrace      = $ErrorObject.ScriptStackTrace
            ErrorMessage          = ''
        }
        if ($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') {
            $httpErrorObj.ErrorMessage = $ErrorObject.ErrorDetails.Message
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            $httpErrorObj.ErrorMessage = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
        }
        Write-Output $httpErrorObj
    }
}

function Resolve-AFASErrorMessage {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory,
            ValueFromPipeline
        )]
        [object]$ErrorObject
    )
    process {
        try {
            $errorObjectConverted = $ErrorObject | ConvertFrom-Json -ErrorAction Stop

            if ($null -ne $errorObjectConverted.externalMessage) {
                $errorMessage = $errorObjectConverted.externalMessage
            }
            else {
                $errorMessage = $errorObjectConverted
            }
        }
        catch {
            $errorMessage = "$($ErrorObject.Exception.Message)"
        }

        Write-Output $errorMessage
    }
}

function Get-ErrorMessage {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory,
            ValueFromPipeline
        )]
        [object]$ErrorObject
    )
    process {
        $errorMessage = [PSCustomObject]@{
            VerboseErrorMessage = $null
            AuditErrorMessage   = $null
        }

        if ( $($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException')) {
            $httpErrorObject = Resolve-HTTPError -ErrorObject $ErrorObject
            
            if (-not[String]::IsNullOrEmpty($httpErrorObject.ErrorMessage)) {
                $errorMessage.VerboseErrorMessage = $httpErrorObject.ErrorMessage
                $errorMessage.AuditErrorMessage = Resolve-AFASErrorMessage -ErrorObject $httpErrorObject.ErrorMessage
            }
            else {
                $errorMessage.VerboseErrorMessage = $ErrorObject.Exception.Message
                $errorMessage.AuditErrorMessage = $ErrorObject.Exception.Message
            }
        }
        
        # If error message empty, fall back on $ex.Exception.Message
        if ([String]::IsNullOrEmpty($errorMessage.VerboseErrorMessage)) {
            $errorMessage.VerboseErrorMessage = $ErrorObject.Exception.Message
        }
        if ([String]::IsNullOrEmpty($errorMessage.AuditErrorMessage)) {
            $errorMessage.AuditErrorMessage = $ErrorObject.Exception.Message
        }

        Write-Output $errorMessage
    }
}
#endregion functions

# Get current account and verify if there are changes
try {
    if ($actionContext.CorrelationConfiguration.Enabled) {
        $correlationProperty = $actionContext.CorrelationConfiguration.accountField
        $correlationValue = $actionContext.CorrelationConfiguration.accountFieldValue
    
        if ([string]::IsNullOrEmpty($correlationProperty)) {
            Write-Warning "Correlation is enabled but not configured correctly."
            Throw "Correlation is enabled but not configured correctly."
        }
    
        if ([string]::IsNullOrEmpty($correlationValue)) {
            Write-Warning "The correlation value for [$correlationProperty] is empty. This is likely a scripting issue."
            Throw "The correlation value for [$correlationProperty] is empty. This is likely a scripting issue."
        }
    }
    else {
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Message = "Configuration of correlation is madatory."
                IsError = $true
            })
        Throw "Configuration of correlation is madatory."
    }

    Write-Verbose "Querying AFAS employee where [$($correlationProperty)] = [$($correlationValue)]"

    # Create authorization headers
    $encodedToken = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($actionContext.Configuration.Token))
    $authValue = "AfasToken $encodedToken"
    $Headers = @{ Authorization = $authValue }
    $Headers.Add("IntegrationId", "45963_140664") # Fixed value - Tools4ever Partner Integration ID

    $splatWebRequest = @{
        Uri             = "$($actionContext.Configuration.BaseUri)/connectors/$($actionContext.Configuration.GetConnector)?filterfieldids=$($correlationProperty)&filtervalues=$($correlationValue)&operatortypes=1"
        Headers         = $headers
        Method          = 'GET'
        ContentType     = "application/json;charset=utf-8"
        UseBasicParsing = $true
    }
    $currentAccount = (Invoke-RestMethod @splatWebRequest -Verbose:$false).rows

    if ($null -eq $currentAccount.Medewerker) {
        throw "No AFAS employee found AFAS employee where [$($correlationProperty)] = [$($correlationValue)]"
    }

    if (-Not($actionContext.DryRun -eq $true)) {
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Action  = "CorrelateAccount"
                Message = "Correlated account [$($currentAccount.Medewerker)] on field [$($correlationProperty)] with value [$($correlationValue)]"
                IsError = $false
            })

        $aRef = [PSCustomObject]@{
            Medewerker     = $currentAccount.Medewerker
            Persoonsnummer = $currentAccount.Persoonsnummer
        }
        $outputContext.AccountCorrelated = $true
        $outputContext.AccountReference = $aRef
    }
    else {
        Write-Warning "DryRun: Would correlate AFAS employee [$($currentAccount.Medewerker)]."
    }


}
catch {
    $ex = $PSItem
    $errorMessage = Get-ErrorMessage -ErrorObject $ex

    Write-Verbose "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage)"

    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Action  = "CorrelateAccount"
            Message = "Error querying AFAS employee where [$($correlationProperty)] = [$($correlationValue)]. Error Message: $($errorMessage.AuditErrorMessage)"
            IsError = $true
        })
}
finally {
    # Check if auditLogs contains errors, if errors are found, set succes to false
    if ($outputContext.AuditLogs.IsError -contains $true) {
        $outputContext.Success = $false
    }
}