#################################################
# HelloID-Conn-Prov-Target-AFAS-Profit-Employees-Import
# PowerShell V2
#################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

function Get-AFASConnectorData {
    param(
        [parameter(Mandatory = $true)]$Headers,
        [parameter(Mandatory = $true)]$BaseUri,
        [parameter(Mandatory = $true)]$Connector,
        [parameter(Mandatory = $true)]$OrderByFieldIds,
        [parameter(Mandatory = $true)]$Filter,
        [parameter(Mandatory = $true)][ref]$data
    )

    try {
        Write-Verbose "Starting downloading objects through get-connector [$connector]"

        $take = 1000
        $skip = 0

        $uri = $BaseUri + "/connectors/" + $Connector + "?$filter&skip=$skip&take=$take&orderbyfieldids=$OrderByFieldIds"
       
        $dataset = Invoke-RestMethod -Method Get -Uri $uri -Headers $Headers -UseBasicParsing

        foreach ($record in $dataset.rows) { [void]$data.Value.add($record) }

        $skip += $take
        while (@($dataset.rows).count -eq $take) {
            $uri = $BaseUri + "/connectors/" + $Connector + "?$filter&skip=$skip&take=$take&orderbyfieldids=$OrderByFieldIds"

            $dataset = Invoke-RestMethod -Method Get -Uri $uri -Headers $Headers -UseBasicParsing

            $skip += $take

            foreach ($record in $dataset.rows) { [void]$data.Value.add($record) }
        }
        Write-Verbose "Downloaded [$($data.Value.count)] records through get-connector [$connector]"
    }
    catch {
        $data.Value = $null

        $ex = $PSItem
        $errorMessage = Get-ErrorMessage -ErrorObject $ex
    
        Write-Verbose "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage)"

        throw "Error querying data from [$uri]. Error Message: $($errorMessage.AuditErrorMessage)"
    }
}

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

try {
    Write-Information 'Starting AFAS Employees account entitlement import'

    # Create authorization headers using OAuth client credentials
    $tokenUri = "$($actionContext.Configuration.BaseUri)/oauth/token"
    Write-Verbose "Requesting OAuth access token from [$tokenUri]"

    $tokenRequestBody = @{
        grant_type    = 'client_credentials'
        client_id     = $actionContext.Configuration.ClientId
        client_secret = $actionContext.Configuration.ClientSecret
    }

    $tokenResponse = Invoke-RestMethod -Method Post -Uri $tokenUri -Body $tokenRequestBody -ContentType 'application/x-www-form-urlencoded' -UseBasicParsing -Verbose:$false

    if ([String]::IsNullOrWhiteSpace([String]$tokenResponse.access_token)) {
        throw "OAuth token endpoint did not return an access_token."
    }

    if ([String]::IsNullOrWhiteSpace([String]$tokenResponse.token_type) -or ([String]$tokenResponse.token_type).ToLowerInvariant() -ne 'bearer') {
        throw "OAuth token endpoint returned an unexpected token_type [$($tokenResponse.token_type)]. Expected [Bearer]."
    }

    $headers = @{ Authorization = "$($tokenResponse.token_type) $($tokenResponse.access_token)" }
    $headers.Add("IntegrationId", "45963_140664") # Fixed value - Tools4ever Partner Integration ID

    #Query persons / accounts
    $importedAccounts = [System.Collections.ArrayList]::new()
    
    #Filter - Determine what defines an account entitlement, copy from AFAS Connect cURL
    $Filter = "filterfieldids=Email_werk&filtervalues=%5Bis%20niet%20leeg%5D&operatortypes=9"

    Get-AFASConnectorData -Headers $headers -BaseUri $($actionContext.Configuration.BaseUri) -Connector $($actionContext.Configuration.GetConnector) -OrderByFieldIds "Medewerker" ([ref]$importedAccounts) -Filter $Filter

    foreach ($importedAccount in $importedAccounts) {
        $data = @{}
        
        $importedAccount | Add-Member -MemberType NoteProperty -Name "EmAd" -Value $($importedAccount.Email_werk) -Force

        foreach ($field in $actionContext.ImportFields) {
            $data[$field] = $importedAccount."$field"
        }

        # Return the result
        Write-Output @{
            AccountReference = [PSCustomObject]@{
                    Medewerker     = $importedAccount.Medewerker
                    Persoonsnummer = $importedAccount.Persoonsnummer
                }
            DisplayName      = $importedAccount.DisplayName
            UserName         = $importedAccount.Email_werk
            Enabled          = $false
            Data             = $data
        }
    }
    
    Write-Information 'AFAS Employees account entitlement import completed'
} catch {
    $ex = $PSItem
    $errorMessage = Get-ErrorMessage -ErrorObject $ex

    Write-Warning "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage)"
    Write-Error "Could not import AFAS Employees account entitlements. Error: $($errorMessage.VerboseErrorMessage)"
}