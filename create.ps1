#####################################################
# HelloID-Conn-Prov-Target-AFAS-Profit-Employees-Create
#
# Version: 2.1.0
#####################################################
# Initialize default values
$c = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$success = $false
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()

# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

# Set debug logging
switch ($($c.isDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}
$InformationPreference = "Continue"
$WarningPreference = "Continue"

# Used to connect to AFAS API endpoints
$BaseUri = $c.BaseUri
$Token = $c.Token
$updateOnCorrelate = $c.updateEmployeeOnCorrelate
$getConnector = "T4E_HelloID_Users_v2"
$updateConnector = "KnEmployee"

# Correlation values
$correlationProperty = "Medewerker" # Has to match the name of the unique identifier
$correlationValue = $p.ExternalId # Has to match the value of the unique identifier

#Change mapping here
$account = [PSCustomObject]@{
    # E-Mail werk  
    'EmAd' = $p.Accounts.MicrosoftActiveDirectory.mail

    # # E-mail toegang - Check with AFAS Administrator if this needs to be set
    # 'EmailPortal' = $p.Accounts.MicrosoftActiveDirectory.userPrincipalName 

    # # Telefoonnr. werk
    # 'TeNr'        = '0229123456'
    
    # # Mobiel werk
    # 'MbNr'        = '0612345678'
}

# Additionally set account properties as required
$requiredFields = @()

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
            $httpErrorObject = Resolve-HTTPError -Error $ErrorObject

            $errorMessage.VerboseErrorMessage = $httpErrorObject.ErrorMessage

            $errorMessage.AuditErrorMessage = Resolve-AFASErrorMessage -ErrorObject $httpErrorObject.ErrorMessage
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
    # Check if required fields are available for correlation
    $incompleteCorrelationValues = $false
    if ([String]::IsNullOrEmpty($correlationProperty)) {
        $incompleteCorrelationValues = $true
        Write-Warning "Required correlation field [correlationProperty] has a null or empty value"
    }
    if ([String]::IsNullOrEmpty($correlationValue)) {
        $incompleteCorrelationValues = $true
        Write-Warning "Required correlation field [correlationValue] has a null or empty value"
    }
    
    if ($incompleteCorrelationValues -eq $true) {
        throw "Correlation values incomplete, cannot continue. CorrelationProperty = [$correlationProperty], CorrelationValue = [$correlationValue]'"
    }

    # Check if required fields are available in account object
    $incompleteAccount = $false
    foreach ($requiredField in $requiredFields) {
        if ($requiredField -notin $account.PsObject.Properties.Name) {
            $incompleteAccount = $true
            Write-Warning "Required account object field [$requiredField] is missing"
        }

        if ([String]::IsNullOrEmpty($account.$requiredField)) {
            $incompleteAccount = $true
            Write-Warning "Required account object field [$requiredField] has a null or empty value"
        }
    }

    if ($incompleteAccount -eq $true) {
        throw "Account object incomplete, cannot continue. Account object: $($account | ConvertTo-Json -Depth 10)"
    }

    # Get current account and verify if the action should be either [updated and correlated] or just [correlated]
    try {
        Write-Verbose "Querying AFAS employee where [$($correlationProperty)] = [$($correlationValue)]"

        # Create authorization headers
        $encodedToken = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($Token))
        $authValue = "AfasToken $encodedToken"
        $Headers = @{ Authorization = $authValue }
        $Headers.Add("IntegrationId", "45963_140664") # Fixed value - Tools4ever Partner Integration ID

        $splatWebRequest = @{
            Uri             = $BaseUri + "/connectors/" + $getConnector + "?filterfieldids=$($correlationProperty)&filtervalues=$($correlationValue)&operatortypes=1"
            Headers         = $headers
            Method          = 'GET'
            ContentType     = "application/json;charset=utf-8"
            UseBasicParsing = $true
        }
        $currentAccount = (Invoke-RestMethod @splatWebRequest -Verbose:$false).rows

        if ($null -eq $currentAccount.Medewerker) {
            throw "No AFAS employee found AFAS employee where [$($correlationProperty)] = [$($correlationValue)]"
        }

        if ($updateOnCorrelate -eq $true) {
            $action = 'Update-Correlate'
        
            $propertiesChanged = $null

            # Retrieve current account data for properties to be updated
            $previousAccount = [PSCustomObject]@{
                # E-Mail werk  
                'EmAd'        = $currentAccount.Email_werk
                # E-mail toegang
                'EmailPortal' = $currentAccount.Email_portal
                # Telefoonnr. werk
                'TeNr'        = $currentAccount.Telefoonnr_werk
                # Mobiel werk
                'MbNr'        = $currentAccount.Mobielnr_werk
            }

            $splatCompareProperties = @{
                ReferenceObject  = @($previousAccount.PSObject.Properties)
                DifferenceObject = @($account.PSObject.Properties)
            }
            $propertiesChanged = (Compare-Object @splatCompareProperties -PassThru).Where( { $_.SideIndicator -eq '=>' })

            if ($propertiesChanged) {
                Write-Verbose "Account property(s) required to update: [$($propertiesChanged.name -join ",")]"

                foreach ($changedProperty in $propertiesChanged) {
                    Write-Warning "Updating property [$($changedProperty.name)]. Current value [$($previousAccount.($changedProperty.name))]. New value [$($account.($changedProperty.name))]"
                }

                $updateAction = 'Update'
            }
            else {
                $updateAction = 'NoChanges'
            }
        }
        else {
            $action = 'Correlate'
        }
    }
    catch {
        $ex = $PSItem
        $errorMessage = Get-ErrorMessage -ErrorObject $ex

        Write-Verbose "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage)"

        if ($errorMessage.AuditErrorMessage -Like "No AFAS employee found AFAS employee where [$($correlationProperty)] = [$($correlationValue)]") {
            $auditLogs.Add([PSCustomObject]@{
                    Action  = "CreateAccount"
                    Message = "No AFAS employee found AFAS employee where [$($correlationProperty)] = [$($correlationValue)]. Possibly deleted."
                    IsError = $true
                })
        }
        else {
            $auditLogs.Add([PSCustomObject]@{
                    # Action  = "" # Optional
                    Message = "Error querying AFAS employee where [$($correlationProperty)] = [$($correlationValue)]. Error Message: $($errorMessage.AuditErrorMessage)"
                    IsError = $true
                })
        }
    }

    if ($null -ne $currentAccount.Medewerker) {
        # Either [update and correlate] or just [correlate]
        switch ($action) {
            'Update-Correlate' {       
                switch ($updateAction) {
                    'Update' {
                        try {
                            # Create custom account object for update and set with default properties and values
                            $updateAccount = [PSCustomObject]@{
                                'AfasEmployee' = @{
                                    'Element' = @{
                                        '@EmId'   = $currentAccount.Medewerker
                                        'Objects' = @(@{
                                                'KnPerson' = @{
                                                    'Element' = @{
                                                        'Fields' = @{
                                                            # Zoek op BcCo (Persoons-ID)
                                                            'MatchPer' = 0
                                                            # Nummer
                                                            'BcCo'     = $currentAccount.Persoonsnummer
                                                        }
                                                    }
                                                }
                                            })
                                    }
                                }
                            }

                            # Add the updated properties to the custom account object for update - Only add changed properties. AFAS will throw an error when trying to update this with the same value
                            foreach ($changedProperty in $propertiesChanged) {
                                $updateAccount.AfasEmployee.Element.Objects[0].KnPerson.Element.Fields.$($changedProperty.Name) = $changedProperty.Value
                            }

                            $body = ($updateAccount | ConvertTo-Json -Depth 10)
                            $splatWebRequest = @{
                                Uri             = $BaseUri + "/connectors/" + $updateConnector
                                Headers         = $headers
                                Method          = 'PUT'
                                Body            = ([System.Text.Encoding]::UTF8.GetBytes($body))
                                ContentType     = "application/json;charset=utf-8"
                                UseBasicParsing = $true
                            }
          
                            Write-Verbose "Updating AFAS employee [$($currentAccount.Medewerker)]. Account object: $($account | ConvertTo-Json -Depth 10)"
                                
                            if (-not($dryRun -eq $true)) {
                                $updatedAccount = Invoke-RestMethod @splatWebRequest -Verbose:$false
    
                                $auditLogs.Add([PSCustomObject]@{
                                        # Action  = "" # Optional
                                        Message = "Successfully updated AFAS employee [$($currentAccount.Medewerker)]"
                                        IsError = $false
                                    })
                            }
                            else {
                                Write-Warning "DryRun: Would update AFAS employee [$($currentAccount.Medewerker)]. Account object: $($account | ConvertTo-Json -Depth 10)"
                            }
    
                            break
                        }
                        catch {
                            $ex = $PSItem
                            $errorMessage = Get-ErrorMessage -ErrorObject $ex
                        
                            Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($($errorMessage.VerboseErrorMessage))"
                    
                            $auditLogs.Add([PSCustomObject]@{
                                    # Action  = "" # Optional
                                    Message = "Error updating AFAS employee [$($currentAccount.Medewerker)]. Error Message: $($errorMessage.AuditErrorMessage). Account object: $($account | ConvertTo-Json -Depth 10)"
                                    IsError = $true
                                })
                        }
                    }
                    'NoChanges' {
                        Write-Verbose "No changes to RAFAS employee [$($currentAccount.Medewerker)]"
        
                        if (-not($dryRun -eq $true)) {
                            $auditLogs.Add([PSCustomObject]@{
                                    # Action  = "" # Optional
                                    Message = "Successfully updated AFAS employee [$($currentAccount.Medewerker)] (No changes needed)"
                                    IsError = $false
                                })
                        }
                        else {
                            Write-Warning "DryRun: No changes to AFAS employee [$($currentAccount.Medewerker)]"
                        }                  
    
                        break
                    }
                }
    
                # Set aRef object for use in futher actions
                $aRef = [PSCustomObject]@{
                    Medewerker     = $currentAccount.Medewerker
                    Persoonsnummer = $currentAccount.Persoonsnummer
                }
    
                # Define ExportData with account fields and correlation property 
                $exportData = $account.PsObject.Copy()
                $exportData | Add-Member -MemberType NoteProperty -Name $correlationProperty -Value $correlationValue -Force
    
                break
            }
            'Correlate' {
                Write-Verbose "Correlating to AFAS employee [$($currentAccount.Medewerker)]"

                if (-not($dryRun -eq $true)) {
                    $auditLogs.Add([PSCustomObject]@{
                            # Action  = "" # Optional
                            Message = "Successfully correlated to AFAS employee [$($currentAccount.Medewerker)]"
                            IsError = $false
                        })
                }
                else {
                    Write-Warning "DryRun: Would correlate to AFAS employee [$($currentAccount.Medewerker)]"
                }

                # Set aRef object for use in futher actions
                $aRef = [PSCustomObject]@{
                    Medewerker     = $currentAccount.Medewerker
                    Persoonsnummer = $currentAccount.Persoonsnummer
                }

                # Define ExportData with account fields and correlation property 
                $exportData = $previousAccount.PsObject.Copy()
                $exportData | Add-Member -MemberType NoteProperty -Name $correlationProperty -Value $correlationValue -Force

                break
            }
        }
    }
}
finally {
    # Check if auditLogs contains errors, if no errors are found, set success to true
    if (-NOT($auditLogs.IsError -contains $true)) {
        $success = $true
    }

    # Send results
    $result = [PSCustomObject]@{
        Success          = $success
        AccountReference = $aRef
        AuditLogs        = $auditLogs
        PreviousAccount  = $previousAccount
        Account          = $account

        # Optionally return data for use in other systems
        ExportData       = $exportData
    }

    Write-Output ($result | ConvertTo-Json -Depth 10)  
}