#####################################################
# HelloID-Conn-Prov-Target-AFAS-Profit-Employees-Delete
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
    # Verify if [accountReference] has a value
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw 'The account reference could not be found'
    }
    if ($actionContext.References.Account -match '[,;]') {
        throw 'Account reference contains a comma or semicolon, which cannot be used in AFAS filter values'
    }

    Write-Information 'Verifying if an AFAS Profit employee exists'

    # Create authorization headers using OAuth client credentials
    $tokenUri = "$($actionContext.Configuration.BaseUri)/oauth/token"
    Write-Verbose "Requesting OAuth access token from [$tokenUri]"

    $tokenRequestBody = @{
        grant_type    = 'client_credentials'
        client_id     = $actionContext.Configuration.ClientId
        client_secret = $actionContext.Configuration.ClientSecret
    }

    $tokenResponse = Invoke-RestMethod -Method Post -Uri $tokenUri -Body $tokenRequestBody -ContentType 'application/x-www-form-urlencoded' -UseBasicParsing -ErrorAction Stop -Verbose:$false

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

    $splatQueryParams = @{
        Uri             = "$($actionContext.Configuration.BaseUri)/connectors/$($actionContext.Configuration.GetConnector)?filterfieldids=EmId&filtervalues=$([uri]::EscapeDataString($actionContext.References.Account))&operatortypes=1"
        Headers         = $headers
        Method          = 'GET'
        ContentType     = 'application/json;charset=utf-8'
        UseBasicParsing = $true
        ErrorAction     = 'Stop'
    }

    $correlatedAccount = @((Invoke-RestMethod @splatQueryParams).rows)

    if ($correlatedAccount.Count -eq 1) {
        $correlatedAccount = $correlatedAccount[0]
        $outputContext.PreviousData = $correlatedAccount | Select-Object -Property $outputContext.Data.PSObject.Properties.Name

        if ([string]::IsNullOrWhiteSpace([string]$correlatedAccount.BcCo)) {
            throw 'Correlated AFAS employee is missing required person number [BcCo]. Verify the AFAS GetConnector output.'
        }

        # During reconciliation no field mapping data is available, so the configured DeleteMode determines the end state.
        if ($actionContext.Origin -eq 'reconciliation') {
            $deleteMode = [string]$actionContext.Configuration.DeleteMode
            switch ($deleteMode) {
                'keepEmAd' {
                    $mappedData = [PSCustomObject]@{}
                    break
                }
                'clearEmAd' {
                    $mappedData = [PSCustomObject]@{ EmAd = '' }
                    break
                }
                default {
                    throw "Unsupported DeleteMode value [$deleteMode]"
                }
            }
        }
        else {
            $mappedData = $actionContext.Data
        }

        # All mapped fields are sent, AFAS accepts a field that is set to its current value. EmId is the element key and BcCo is only used to match KnPerson. Both are never updated by HelloID.
        $fieldsToUpdate = @($mappedData.PSObject.Properties | Where-Object { $_.Name -notin @('EmId', 'BcCo') })

        if ($fieldsToUpdate.Count -gt 0) {
            $lifecycleProcess = 'DeleteAccount'
        }
        else {
            $lifecycleProcess = 'NoChanges'
        }
    }
    elseif ($correlatedAccount.Count -gt 1) {
        throw "Multiple AFAS Profit employees found with accountReference: [$($actionContext.References.Account)]"
    }
    else {
        $lifecycleProcess = 'NotFound'
    }

    # Process
    switch ($lifecycleProcess) {
        'DeleteAccount' {
            $fieldsInPayload = $fieldsToUpdate.Name -join ', '

            # Free fields (U + GUID) of the employee belong on the AfasEmployee element, all other fields on the KnPerson element.
            $employeeFields = [ordered]@{}
            $personFields = [ordered]@{
                MatchPer = 0 # Match the person on BcCo
                BcCo     = $correlatedAccount.BcCo
            }
            foreach ($property in $fieldsToUpdate) {
                # AFAS clears text fields with an empty string, not with JSON null.
                $value = if ($null -eq $property.Value) { '' } else { $property.Value }
                if ($property.Name -match '^U[0-9A-Fa-f]{32}$') {
                    $employeeFields[$property.Name] = $value
                }
                else {
                    $personFields[$property.Name] = $value
                }
            }

            $element = [ordered]@{
                '@EmId' = $correlatedAccount.EmId
            }
            if ($employeeFields.Count -gt 0) {
                $element['Fields'] = $employeeFields
            }
            $element['Objects'] = @(
                @{
                    KnPerson = @{
                        Element = @{
                            Fields = $personFields
                        }
                    }
                }
            )

            $body = ([PSCustomObject]@{ AfasEmployee = @{ Element = $element } } | ConvertTo-Json -Depth 10)
            $splatUpdateParams = @{
                Uri             = "$($actionContext.Configuration.BaseUri)/connectors/$($actionContext.Configuration.UpdateConnector)"
                Headers         = $headers
                Method          = 'PUT'
                Body            = ([System.Text.Encoding]::UTF8.GetBytes($body))
                ContentType     = 'application/json;charset=utf-8'
                UseBasicParsing = $true
                ErrorAction     = 'Stop'
            }

            if (-not($actionContext.DryRun -eq $true)) {
                Write-Information "Deleting AFAS Profit employee with accountReference: [$($actionContext.References.Account)]. Update payload fields: [$fieldsInPayload]"
                $null = Invoke-RestMethod @splatUpdateParams -Verbose:$false
                $auditLogMessage = "Delete AFAS Profit employee with accountReference: [$($actionContext.References.Account)] was successful. Update payload fields: [$fieldsInPayload]"
            }
            else {
                Write-Information "[DryRun] Delete AFAS Profit employee with accountReference: [$($actionContext.References.Account)], will be executed during enforcement. Update payload fields: [$fieldsInPayload]"
                $auditLogMessage = "[DryRun] Would delete AFAS Profit employee with accountReference: [$($actionContext.References.Account)]. Update payload fields: [$fieldsInPayload]"
            }

            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = $auditLogMessage
                    IsError = $false
                })
            break
        }

        'NoChanges' {
            Write-Information "No changes to AFAS Profit employee with accountReference: [$($actionContext.References.Account)]"

            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Delete AFAS Profit employee with accountReference: [$($actionContext.References.Account)] was successful. No changes required in AFAS"
                    IsError = $false
                })
            break
        }

        'NotFound' {
            Write-Information "AFAS Profit employee: [$($actionContext.References.Account)] could not be found, indicating that it may have been deleted or is out of scope of the GetConnector"

            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "AFAS Profit employee: [$($actionContext.References.Account)] could not be found, indicating that it may have been deleted or is out of scope of the GetConnector"
                    IsError = $false
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
        $auditLogMessage = "Could not delete AFAS Profit employee: [$($actionContext.References.Account)]. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditLogMessage = "Could not delete AFAS Profit employee: [$($actionContext.References.Account)]. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditLogMessage
            IsError = $true
        })
}
