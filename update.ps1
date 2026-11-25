#####################################################
# HelloID-Conn-Prov-Target-AFAS-Profit-Employees-Update
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

    Write-Information 'Verifying if an AFAS Profit employee exists'

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

    $splatQueryParams = @{
        Uri             = "$($actionContext.Configuration.BaseUri)/connectors/$($actionContext.Configuration.GetConnector)?filterfieldids=EmId&filtervalues=$([uri]::EscapeDataString($actionContext.References.Account))&operatortypes=1"
        Headers         = $headers
        Method          = 'GET'
        ContentType     = 'application/json;charset=utf-8'
        UseBasicParsing = $true
        ErrorAction     = 'Stop'
        Verbose         = $false
    }

    $correlatedAccount = @((Invoke-RestMethod @splatQueryParams).rows)

    if ($correlatedAccount.Count -eq 1) {
        $correlatedAccount = $correlatedAccount[0]
        $outputContext.AccountReference = [string]$correlatedAccount.EmId
        $outputContext.PreviousData = $correlatedAccount | Select-Object -Property $outputContext.Data.PSObject.Properties.Name

        if ([string]::IsNullOrWhiteSpace([string]$correlatedAccount.BcCo)) {
            throw 'Correlated AFAS employee is missing required person number [BcCo]. Verify the AFAS GetConnector output.'
        }

        # Compare mapped values with the current AFAS values. Only changed fields are sent, so the audit log shows the actual changes.
        $accountPropertiesChanged = [System.Collections.Generic.List[object]]::new()
        foreach ($property in $actionContext.Data.PSObject.Properties) {
            # EmId is the element key and BcCo is only used to match KnPerson. Both are never updated by HelloID.
            # Mapped fields that are not in the GetConnector cannot be compared and are skipped.
            $currentProperty = $correlatedAccount.PSObject.Properties[$property.Name]
            if ($property.Name -in @('EmId', 'BcCo') -or $null -eq $currentProperty) {
                continue
            }

            # An empty or null mapped value clears the field in AFAS. AFAS clears text fields with an empty string, not with JSON null. AFAS returns empty fields as null, which compares as an empty string.
            $mappedValue = if ($null -eq $property.Value) { '' } else { $property.Value }

            # Normalize values to avoid type-based changes.
            if ($mappedValue -is [string] -and $mappedValue -match '^(true|false)$') {
                $mappedValue = [bool]::Parse($mappedValue)
            }
            $mappedComparisonValue = if ($mappedValue -is [bool]) { $mappedValue.ToString().ToLowerInvariant() } else { [string]$mappedValue }
            $currentComparisonValue = if ($currentProperty.Value -is [bool]) { $currentProperty.Value.ToString().ToLowerInvariant() } else { [string]$currentProperty.Value }

            if ($mappedComparisonValue -ne $currentComparisonValue) {
                $accountPropertiesChanged.Add([PSCustomObject]@{ Name = $property.Name; Value = $mappedValue })
            }
        }

        if ($accountPropertiesChanged.Count -gt 0) {
            $lifecycleProcess = 'UpdateAccount'
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
        'UpdateAccount' {
            Write-Information "Account property(s) required to update: $($accountPropertiesChanged.Name -join ', ')"

            # Free fields (U + GUID) of the employee belong on the AfasEmployee element, all other fields on the KnPerson element.
            $employeeFields = [ordered]@{}
            $personFields = [ordered]@{
                MatchPer = 0 # Match the person on BcCo
                BcCo     = $correlatedAccount.BcCo
            }
            foreach ($property in $accountPropertiesChanged) {
                if ($property.Name -match '^U[0-9A-Fa-f]{32}$') {
                    $employeeFields[$property.Name] = $property.Value
                }
                else {
                    $personFields[$property.Name] = $property.Value
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
                Verbose         = $false
            }

            if (-not($actionContext.DryRun -eq $true)) {
                Write-Information "Updating AFAS Profit employee with accountReference: [$($actionContext.References.Account)]"
                $null = Invoke-RestMethod @splatUpdateParams
            }
            else {
                Write-Information "[DryRun] Update AFAS Profit employee with accountReference: [$($actionContext.References.Account)], will be executed during enforcement"
            }

            # Update outputContext.Data with changed values only, leaving unchanged values as-is.
            foreach ($property in $accountPropertiesChanged) {
                $outputContext.Data | Add-Member -MemberType NoteProperty -Name $property.Name -Value $property.Value -Force
            }
            $outputContext.Data | Add-Member -MemberType NoteProperty -Name 'BcCo' -Value $correlatedAccount.BcCo -Force
            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Update account was successful, Account property(s) updated: [$($accountPropertiesChanged.Name -join ',')]"
                    IsError = $false
                })
            break
        }

        'NoChanges' {
            Write-Information "No changes to AFAS Profit employee with accountReference: [$($actionContext.References.Account)]"

            $outputContext.Data | Add-Member -MemberType NoteProperty -Name 'BcCo' -Value $correlatedAccount.BcCo -Force
            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Skipped updating AFAS Profit employee with accountReference: [$($actionContext.References.Account)]. Reason: No changes."
                    IsError = $false
                })
            break
        }

        'NotFound' {
            Write-Information "AFAS Profit employee with accountReference: [$($actionContext.References.Account)] could not be found, indicating that it may have been deleted or is out of scope of the GetConnector"

            $outputContext.Success = $false
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "AFAS Profit employee with accountReference: [$($actionContext.References.Account)] could not be found, indicating that it may have been deleted or is out of scope of the GetConnector"
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
        $auditLogMessage = "Could not update AFAS Profit employee: [$($actionContext.References.Account)]. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditLogMessage = "Could not update AFAS Profit employee: [$($actionContext.References.Account)]. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }

    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditLogMessage
            IsError = $true
        })
}
