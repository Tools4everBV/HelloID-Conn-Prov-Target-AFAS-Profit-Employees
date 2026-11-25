#####################################################
# HelloID-Conn-Prov-Target-AFAS-Profit-Employees-Create
# PowerShell V2
#####################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

#region functions
function Resolve-AFASProfitError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            ScriptLineNumber = $ErrorObject.InvocationInfo.ScriptLineNumber
            Line             = $ErrorObject.InvocationInfo.Line
            ErrorDetails     = $ErrorObject.Exception.Message
            FriendlyMessage  = $ErrorObject.Exception.Message
        }
        if (-not [string]::IsNullOrEmpty($ErrorObject.ErrorDetails.Message)) {
            $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails.Message
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            if ($null -ne $ErrorObject.Exception.Response) {
                $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
                if (-not [string]::IsNullOrEmpty($streamReaderResponse)) {
                    $httpErrorObj.ErrorDetails = $streamReaderResponse
                }
            }
        }
        try {
            $errorDetailsObject = ($httpErrorObj.ErrorDetails | ConvertFrom-Json)
            if ($null -ne $errorDetailsObject.externalMessage) {
                $httpErrorObj.FriendlyMessage = $errorDetailsObject.externalMessage
            }
            else {
                $httpErrorObj.FriendlyMessage = $errorDetailsObject
            }
        }
        catch {
            $httpErrorObj.FriendlyMessage = "[$($httpErrorObj.ErrorDetails)]"
        }
        Write-Output $httpErrorObj
    }
}
#endregion

try {
    # Initial Assignments
    $outputContext.AccountReference = 'Currently not available'

    # Validate correlation configuration
    if ($actionContext.CorrelationConfiguration.Enabled) {
        $correlationField = $actionContext.CorrelationConfiguration.AccountField
        $correlationValue = $actionContext.CorrelationConfiguration.PersonFieldValue

        if ([string]::IsNullOrEmpty($($correlationField))) {
            throw 'Correlation is enabled but not configured correctly'
        }
        if ([string]::IsNullOrEmpty($($correlationValue))) {
            throw 'Correlation is enabled but [accountFieldValue] is empty. Please make sure it is correctly mapped'
        }

        Write-Information "Verifying if an AFAS Profit employee exists where $correlationField is: [$correlationValue]"

        $tokenRequestBody = @{
            grant_type    = 'client_credentials'
            client_id     = $actionContext.Configuration.ClientId
            client_secret = $actionContext.Configuration.ClientSecret
        }

        $splatTokenParams = @{
            Uri             = "$($actionContext.Configuration.BaseUri)/oauth/token"
            Method          = 'POST'
            Body            = $tokenRequestBody
            ContentType     = 'application/x-www-form-urlencoded'
            UseBasicParsing = $true
            ErrorAction     = 'Stop'
            Verbose         = $false
        }

        $tokenResponse = Invoke-RestMethod @splatTokenParams

        if ([String]::IsNullOrWhiteSpace([String]$tokenResponse.access_token)) {
            throw 'OAuth token endpoint did not return an access_token.'
        }

        if ([String]::IsNullOrWhiteSpace([String]$tokenResponse.token_type) -or ([String]$tokenResponse.token_type).ToLowerInvariant() -ne 'bearer') {
            throw "OAuth token endpoint returned an unexpected token_type [$($tokenResponse.token_type)]. Expected [Bearer]."
        }

        $headers = @{
            Authorization = "$($tokenResponse.token_type) $($tokenResponse.access_token)"
            IntegrationId = '45963_140664' # Fixed value - Tools4ever Partner Integration ID
        }

        # BcCo is required to match the KnPerson record in the update payload.
        $notEmptyFilterValue = [uri]::EscapeDataString('[is niet leeg]')
        $splatQueryParams = @{
            Uri             = "$($actionContext.Configuration.BaseUri)/connectors/$($actionContext.Configuration.GetConnector)?filterfieldids=$($correlationField),BcCo&filtervalues=$([uri]::EscapeDataString($correlationValue)),$notEmptyFilterValue&operatortypes=1,9"
            Method          = 'GET'
            Headers         = $headers
            ContentType     = 'application/json;charset=utf-8'
            UseBasicParsing = $true
            ErrorAction     = 'Stop'
            Verbose         = $false
        }

        $correlatedAccount = @((Invoke-RestMethod @splatQueryParams).rows)
    }
    else {
        throw 'Correlation is not enabled but this connector only supports correlation.'
    }

    if ($correlatedAccount.Count -eq 0) {
        $lifecycleProcess = 'NotFound'
    }
    elseif ($correlatedAccount.Count -eq 1) {
        $correlatedAccount = $correlatedAccount[0]
        $lifecycleProcess = 'CorrelateAccount'
    }
    elseif ($correlatedAccount.Count -gt 1) {
        throw "Multiple employees found for person where $correlationField is: [$correlationValue]"
    }

    # Process
    switch ($lifecycleProcess) {
        'CorrelateAccount' {
            Write-Information "Correlating AFAS Profit employee [$($correlatedAccount.EmId)]"

            $outputContext.Data = $correlatedAccount | Select-Object -Property $outputContext.Data.PSObject.Properties.Name
            $outputContext.AccountReference = [string]$correlatedAccount.EmId
            $outputContext.AccountCorrelated = $true
            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Action  = 'CorrelateAccount'
                    Message = "Correlated account: [$($outputContext.AccountReference)] on field: [$($correlationField)] with value: [$($correlationValue)]"
                    IsError = $false
                })
            break
        }

        'NotFound' {
            $auditLogMessage = "No AFAS Profit employee found where [$($correlationField)] = [$($correlationValue)] with a person number [BcCo]. This connector only supports correlation."
            Write-Information $auditLogMessage

            $outputContext.Success = $false
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Action  = 'CorrelateAccount'
                    Message = $auditLogMessage
                    IsError = $true
                })
            break
        }
    }
}
catch {
    $outputContext.Success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-AFASProfitError -ErrorObject $ex
        $auditLogMessage = "Could not correlate AFAS Profit employee. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditLogMessage = "Could not correlate AFAS Profit employee. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Action  = 'CorrelateAccount'
            Message = $auditLogMessage
            IsError = $true
        })
}
