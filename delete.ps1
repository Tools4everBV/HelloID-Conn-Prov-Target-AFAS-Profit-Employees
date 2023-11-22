#####################################################
# HelloID-Conn-Prov-Target-AFAS-Profit-Employees-Delete
#
# Version: 2.1.0
#####################################################
# Initialize default values
$c = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$aRef = $accountReference | ConvertFrom-Json
$success = $false # Set to false at start, at the end, only when no error occurs it is set to true
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()

# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

# Set debug logging
switch ($($c.isDebug)) {
    $true { $VerbosePreference = "Continue" }
    $false { $VerbosePreference = "SilentlyContinue" }
}
$InformationPreference = "Continue"
$WarningPreference = "Continue"

# Correlation values
$correlationProperty = "Medewerker" # Has to match the name of the unique identifier
$correlationValue = $p.ExternalId # Has to match the value of the unique identifier

#Change mapping here
$account = [PSCustomObject]@{
    # E-Mail werk  
    'EmAd'        = "" # or e.g. "$($aRef.Medewerker)@domain.com" - Unique value because at the revoke action we want to clear the unique fields

    # E-mail toegang - Check with AFAS Administrator if this needs to be set
    'EmailPortal' = "" # or e.g. "$($aRef.Medewerker)@domain.com" - Unique value because at the revoke action we want to clear the unique fields

    # # Telefoonnr. werk
    # 'TeNr'        = '0229123456'
    
    # # Mobiel werk
    # 'MbNr'        = '0612345678'
}

# Define account properties to update
$updateAccountFields = @("EmAd")

# Define account properties to store in account data
$storeAccountFields = @("EmAd", "EmailPortal")

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
    # Get current account and verify if there are changes
    try {
        Write-Verbose "Querying AFAS employee where [$($correlationProperty)] = [$($correlationValue)]"

        # Create authorization headers
        $encodedToken = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($c.Token))
        $authValue = "AfasToken $encodedToken"
        $Headers = @{ Authorization = $authValue }
        $Headers.Add("IntegrationId", "45963_140664") # Fixed value - Tools4ever Partner Integration ID

        $splatWebRequest = @{
            Uri             = "$($c.BaseUri)/connectors/$($c.GetConnector)?filterfieldids=$($correlationProperty)&filtervalues=$($correlationValue)&operatortypes=1"
            Headers         = $headers
            Method          = 'GET'
            ContentType     = "application/json;charset=utf-8"
            UseBasicParsing = $true
        }
        $currentAccount = (Invoke-RestMethod @splatWebRequest -Verbose:$false).rows

        if ($null -eq $currentAccount.Medewerker) {
            throw "No AFAS employee found AFAS employee where [$($correlationProperty)] = [$($correlationValue)]"
        }

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

        # Calculate changes between current data and provided data
        $splatCompareProperties = @{
            ReferenceObject  = @($previousAccount.PSObject.Properties | Where-Object { $_.Name -in $updateAccountFields }) # Only select the properties to update
            DifferenceObject = @($account.PSObject.Properties | Where-Object { $_.Name -in $updateAccountFields }) # Only select the properties to update
        }
        $changedProperties = $null
        $changedProperties = (Compare-Object @splatCompareProperties -PassThru)
        $oldProperties = $changedProperties.Where( { $_.SideIndicator -eq '<=' })
        $newProperties = $changedProperties.Where( { $_.SideIndicator -eq '=>' })

        if (($newProperties | Measure-Object).Count -ge 1) {
            Write-Verbose "Changed properties: $($changedProperties | ConvertTo-Json)"

            $updateAction = 'Update'
        }
        else {
            Write-Verbose "No changed properties"
            
            $updateAction = 'NoChanges'
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

        # Skip further actions, as this is a critical error
        continue
    }
 
    switch ($updateAction) {
        'Update' {
            # Update AFAS Employee
            try {
                # Create custom object with old and new values
                $changedPropertiesObject = [PSCustomObject]@{
                    OldValues = @{}
                    NewValues = @{}
                }

                # Add the old properties to the custom object with old and new values
                foreach ($oldProperty in ($oldProperties | Where-Object { $_.Name -in $newProperties.Name })) {
                    $changedPropertiesObject.OldValues.$($oldProperty.Name) = $oldProperty.Value
                }

                # Add the new properties to the custom object with old and new values
                foreach ($newProperty in $newProperties) {
                    $changedPropertiesObject.NewValues.$($newProperty.Name) = $newProperty.Value
                }
                Write-Verbose "Changed properties: $($changedPropertiesObject | ConvertTo-Json)"

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
                foreach ($newProperty in $newProperties ) {
                    $updateAccount.AfasEmployee.Element.Objects[0].KnPerson.Element.Fields.$($newProperty.Name) = $newProperty.Value
                }

                $body = ($updateAccount | ConvertTo-Json -Depth 10)
                $splatWebRequest = @{
                    Uri             = "$($c.BaseUri)/connectors/$($c.UpdateConnector)"
                    Headers         = $headers
                    Method          = 'PUT'
                    Body            = ([System.Text.Encoding]::UTF8.GetBytes($body))
                    ContentType     = "application/json;charset=utf-8"
                    UseBasicParsing = $true
                }

                if (-not($dryRun -eq $true)) {
                    Write-Verbose "Updating AFAS employee [$($currentAccount.Medewerker)]. Old values: $($changedPropertiesObject.oldValues | ConvertTo-Json -Depth 10). New values: $($changedPropertiesObject.newValues | ConvertTo-Json -Depth 10)"
                        
                    $updatedAccount = Invoke-RestMethod @splatWebRequest -Verbose:$false

                    # Set aRef object for use in futher actions
                    $aRef = [PSCustomObject]@{
                        Medewerker     = $currentAccount.Medewerker
                        Persoonsnummer = $currentAccount.Persoonsnummer
                    }
                        
                    $auditLogs.Add([PSCustomObject]@{
                            # Action  = "" # Optional
                            Message = "Successfully updated AFAS employee [$($currentAccount.Medewerker)]. Old values: $($changedPropertiesObject.oldValues | ConvertTo-Json -Depth 10). New values: $($changedPropertiesObject.newValues | ConvertTo-Json -Depth 10)"
                            IsError = $false
                        })
                }
                else {
                    Write-Warning "DryRun: Would update AFAS employee [$($currentAccount.Medewerker)]. Old values: $($changedPropertiesObject.oldValues | ConvertTo-Json -Depth 10). New values: $($changedPropertiesObject.newValues | ConvertTo-Json -Depth 10)"
                }
            }
            catch {
                $ex = $PSItem
                $errorMessage = Get-ErrorMessage -ErrorObject $ex
                    
                Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage)"
                
                $auditLogs.Add([PSCustomObject]@{
                        # Action  = "" # Optional
                        Message = "Error updating AFAS employee [$($currentAccount.Medewerker)]. Error Message: $($errorMessage.AuditErrorMessage). Old values: $($changedPropertiesObject.oldValues | ConvertTo-Json -Depth 10). New values: $($changedPropertiesObject.newValues | ConvertTo-Json -Depth 10)"
                        IsError = $true
                    })
            }

            break
        }
        'NoChanges' {
            Write-Verbose "No changes needed for AFAS employee [$($currentAccount.Medewerker)]"

            if (-not($dryRun -eq $true)) {
                # Set aRef object for use in futher actions
                $aRef = [PSCustomObject]@{
                    Medewerker     = $currentAccount.Medewerker
                    Persoonsnummer = $currentAccount.Persoonsnummer
                }

                $auditLogs.Add([PSCustomObject]@{
                        # Action  = "" # Optional
                        Message = "No changes needed for AFAS employee [$($currentAccount.Medewerker)]"
                        IsError = $false
                    })
            }
            else {
                Write-Warning "DryRun: No changes needed for AFAS employee [$($currentAccount.Medewerker)]"
            }

            break
        }
    }

    # Define ExportData with account fields and correlation property 
    $exportData = $account.PsObject.Copy() | Select-Object $storeAccountFields
    # Add correlation property to exportdata
    $exportData | Add-Member -MemberType NoteProperty -Name $correlationProperty -Value $correlationValue -Force
    # Add aRef properties to exportdata
    foreach ($aRefProperty in $aRef.PSObject.Properties) {
        $exportData | Add-Member -MemberType NoteProperty -Name $aRefProperty.Name -Value $aRefProperty.Value -Force
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