#####################################################
# HelloID-Conn-Prov-Target-AFAS-Profit-Employees-Update
#
# Version: 1.2.0
#####################################################
# Initialize default values
$c = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$aRef = $accountReference | ConvertFrom-Json
$success = $true # Set to true at start, because only when an error occurs it is set to false
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()

# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

$VerbosePreference = "SilentlyContinue"
$InformationPreference = "Continue"
$WarningPreference = "Continue"

# Set debug logging
switch ($($c.isDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

# Used to connect to AFAS API endpoints
$BaseUri = $c.BaseUri
$Token = $c.Token
$getConnector = "T4E_HelloID_Users_v2"
$updateConnector = "KnEmployee"
$account = [PSCustomObject]@{
    'AfasEmployee' = @{
        'Element' = @{
            'Objects' = @(
                @{
                    'KnPerson' = @{
                        'Element' = @{
                            'Fields' = @{
                                # E-Mail werk  
                                'EmAd' = $p.Accounts.MicrosoftActiveDirectory.mail

                                # # E-mail toegang - Check with AFAS Administrator if this needs to be set
                                # 'EmailPortal' = $p.Accounts.MicrosoftActiveDirectory.userPrincipalName 
                            
                                # # Telefoonnr. werk
                                # 'TeNr'        = '0229123456'
                                
                                # # Mobiel werk
                                # 'MbNr'        = '0612345678'
                            }
                        }
                    }
                }
            )
        }
    }
}
# # Troubleshooting
# $dryRun = $false

$filterfieldid = "Medewerker"
$filtervalue = $aRef.Medewerker # Has to match the AFAS value of the specified filter field ($filterfieldid)

#region functions
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
#endregion functions

# Get current AFAS employee and verify if a user must be either [created], [updated and correlated] or just [correlated]
try {
    Write-Verbose "Querying AFAS employee with $($filterfieldid) $($filtervalue)"

    # Create authorization headers
    $encodedToken = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($Token))
    $authValue = "AfasToken $encodedToken"
    $Headers = @{ Authorization = $authValue }

    $splatWebRequest = @{
        Uri             = $BaseUri + "/connectors/" + $getConnector + "?filterfieldids=$filterfieldid&filtervalues=$filtervalue&operatortypes=1"
        Headers         = $headers
        Method          = 'GET'
        ContentType     = "application/json;charset=utf-8"
        UseBasicParsing = $true
    }
    $currentAccount = (Invoke-RestMethod @splatWebRequest -Verbose:$false).rows

    if ($null -eq $currentAccount.Medewerker) {
        throw "No AFAS employee found with $($filterfieldid) $($filtervalue)"
    }

    # Check if current EmAd, EmailPortal, TeNr or MbNr has a different value from mapped value. AFAS will throw an error when trying to update this with the same value
    if ([string]$currentAccount.Email_werk -ne $account.'AfasEmployee'.'Element'.Objects[0].'KnPerson'.'Element'.'Fields'.'EmAd' -and $null -ne $account.'AfasEmployee'.'Element'.Objects[0].'KnPerson'.'Element'.'Fields'.'EmAd') {
        $propertiesChanged += @('EmAd')
    }
    if ([string]$currentAccount.Email_portal -ne $account.'AfasEmployee'.'Element'.Objects[0].'KnPerson'.'Element'.'Fields'.'EmailPortal' -and $null -ne $account.'AfasEmployee'.'Element'.Objects[0].'KnPerson'.'Element'.'Fields'.'EmailPortal') {
        $propertiesChanged += @('EmailPortal')
    }
    if ([string]$currentAccount.Telefoonnr_werk -ne $account.'AfasEmployee'.'Element'.Objects[0].'KnPerson'.'Element'.'Fields'.'TeNr' -and $null -ne $account.'AfasEmployee'.'Element'.Objects[0].'KnPerson'.'Element'.'Fields'.'TeNr') {
        $propertiesChanged += @('TeNr')
    }
    if ([string]$currentAccount.Mobielnr_werk -ne $account.'AfasEmployee'.'Element'.Objects[0].'KnPerson'.'Element'.'Fields'.'MbNr' -and $null -ne $account.'AfasEmployee'.'Element'.Objects[0].'KnPerson'.'Element'.'Fields'.'MbNr') {
        $propertiesChanged += @('MbNr')
    }
    if ($propertiesChanged) {
        Write-Verbose "Account property(s) required to update: [$($propertiesChanged.name -join ",")]"
        $updateAction = 'Update'
    }
    else {
        $updateAction = 'NoChanges'
    }
}
catch {
    $ex = $PSItem
    $verboseErrorMessage = $ex
    Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($verboseErrorMessage)"

    $auditErrorMessage = Resolve-AFASErrorMessage -ErrorObject $ex
    if ($auditErrorMessage -Like "No AFAS employee found with $($filterfieldid) $($filtervalue)") {
        if (-Not($dryRun -eq $True)) {
            $success = $false
            $auditLogs.Add([PSCustomObject]@{
                    Action  = "UpdateAccount"
                    Message = "No AFAS employee found with $($filterfieldid) $($filtervalue). Possibly deleted."
                    IsError = $true
                })
        }
        else {
            Write-Warning "DryRun: No AFAS employee found with $($filterfieldid) $($filtervalue). Possibly deleted."
        }        
    }
    else {
        $success = $false  
        $auditLogs.Add([PSCustomObject]@{
                Action  = "UpdateAccount"
                Message = "Error querying AFAS employee found with $($filterfieldid) $($filtervalue). Error Message: $auditErrorMessage"
                IsError = $True
            })
    }
}

# Update AFAS Employee
$emailBusinessUpdated = $false
$emailPortalUpdated = $false
$telephoneNumberUpdated = $false
$mobileUpdated = $false
if ($null -ne $currentAccount.Medewerker) {
    switch ($updateAction) {
        'Update' {
            try {
                # Create custom account object for update
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

                # Check if currentEmAd, EmailPortal, TeNr or MbNr has a different value from mapped value. AFAS will throw an error when trying to update this with the same value
                if ('EmAd' -in $propertiesChanged) {
                    # E-mail werk
                    $updateAccount.'AfasEmployee'.'Element'.Objects[0].'KnPerson'.'Element'.'Fields'.'EmAd' = $account.'AfasEmployee'.'Element'.Objects[0].'KnPerson'.'Element'.'Fields'.'EmAd'
                    $emailBusinessUpdated = $true
                    if (-not($dryRun -eq $true)) {
                        Write-Information "Updating BusinessEmailAddress '$($currentAccount.Email_werk)' with new value '$($updateAccount.'AfasEmployee'.'Element'.Objects[0].'KnPerson'.'Element'.'Fields'.'EmAd')'"
                    }
                    else {
                        Write-Warning "DryRun: Would update BusinessEmailAddress '$($currentAccount.Email_werk)' with new value '$($updateAccount.'AfasEmployee'.'Element'.Objects[0].'KnPerson'.'Element'.'Fields'.'EmAd')'"
                    }
                }

                if ('EmailPortal' -in $propertiesChanged) {
                    # E-Mail toegang
                    $updateAccount.'AfasEmployee'.'Element'.Objects[0].'KnPerson'.'Element'.'Fields'.'EmailPortal' = $account.'AfasEmployee'.'Element'.Objects[0].'KnPerson'.'Element'.'Fields'.'EmailPortal'
                    $emailBusinessUpdated = $true
                    if (-not($dryRun -eq $true)) {
                        Write-Information "Updating BusinessEmailAddress '$($currentAccount.Email_portal)' with new value '$($updateAccount.'AfasEmployee'.'Element'.Objects[0].'KnPerson'.'Element'.'Fields'.'EmailPortal')'"
                    }
                    else {
                        Write-Warning "DryRun: Would update BusinessEmailAddress '$($currentAccount.Email_portal)' with new value '$($updateAccount.'AfasEmployee'.'Element'.Objects[0].'KnPerson'.'Element'.'Fields'.'EmailPortal')'"
                    }
                }

                if ('TeNr' -in $propertiesChanged) {
                    # Telefoonnr. werk
                    $updateAccount.'AfasEmployee'.'Element'.Objects[0].'KnPerson'.'Element'.'Fields'.'TeNr' = $account.'AfasEmployee'.'Element'.Objects[0].'KnPerson'.'Element'.'Fields'.'TeNr'
                    $emailBusinessUpdated = $true
                    if (-not($dryRun -eq $true)) {
                        Write-Information "Updating BusinessEmailAddress '$($currentAccount.Telefoonnr_werk)' with new value '$($updateAccount.'AfasEmployee'.'Element'.Objects[0].'KnPerson'.'Element'.'Fields'.'TeNr')'"
                    }
                    else {
                        Write-Warning "DryRun: Would update BusinessEmailAddress '$($currentAccount.Telefoonnr_werk)' with new value '$($updateAccount.'AfasEmployee'.'Element'.Objects[0].'KnPerson'.'Element'.'Fields'.'TeNr')'"
                    }
                }

                if ('MbNr' -in $propertiesChanged) {
                    # Mobiel werk
                    $updateAccount.'AfasEmployee'.'Element'.Objects[0].'KnPerson'.'Element'.'Fields'.'MbNr' = $account.'AfasEmployee'.'Element'.Objects[0].'KnPerson'.'Element'.'Fields'.'MbNr'
                    $emailBusinessUpdated = $true
                    if (-not($dryRun -eq $true)) {
                        Write-Information "Updating BusinessEmailAddress '$($currentAccount.Mobielnr_werk)' with new value '$($updateAccount.'AfasEmployee'.'Element'.Objects[0].'KnPerson'.'Element'.'Fields'.'MbNr')'"
                    }
                    else {
                        Write-Warning "DryRun: Would update BusinessEmailAddress '$($currentAccount.Mobielnr_werk)' with new value '$($updateAccount.'AfasEmployee'.'Element'.Objects[0].'KnPerson'.'Element'.'Fields'.'MbNr')'"
                    }
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

                if (-not($dryRun -eq $true)) {
                    $updatedAccount = Invoke-RestMethod @splatWebRequest -Verbose:$false

                    $auditLogs.Add([PSCustomObject]@{
                            Action  = "UpdateAccount"
                            Message = "Successfully updated AFAS employee $($currentAccount.Medewerker)"
                            IsError = $false
                        })
                }
                else {
                    Write-Warning "DryRun: Would update AFAS employee $($currentAccount.Medewerker)"
                }
                break
            }
            catch {
                $ex = $PSItem
                $verboseErrorMessage = $ex
                Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($verboseErrorMessage)"
                
                $auditErrorMessage = Resolve-AFASErrorMessage -ErrorObject $ex
                
                $success = $false  
                $auditLogs.Add([PSCustomObject]@{
                        Action  = "UpdateAccount"
                        Message = "Error updating AFAS employee $($currentAccount.Medewerker). Error Message: $auditErrorMessage"
                        IsError = $True
                    })
            }
        }
        'NoChanges' {
            Write-Verbose "No changes to AFAS employee $($currentAccount.Medewerker)"

            if (-not($dryRun -eq $true)) {
                $auditLogs.Add([PSCustomObject]@{
                        Action  = "UpdateAccount"
                        Message = "Successfully updated AFAS employee $($currentAccount.Medewerker). (No Changes needed)"
                        IsError = $false
                    })
            }
            else {
                Write-Warning "DryRun: No changes to AFAS employee $($currentAccount.Medewerker)"
            }
            break
        }
    }
}

# Send results
$result = [PSCustomObject]@{
    Success          = $success
    AccountReference = $aRef
    AuditLogs        = $auditLogs
    Account          = $account
    PreviousAccount  = $previousAccount    

    # Optionally return data for use in other systems
    ExportData       = [PSCustomObject]@{
        Medewerker     = $aRef.Medewerker
        Persoonsnummer = $aRef.Persoonsnummer      
    }
}

# Only add the data to ExportData if it has actually been updated, since we want to store the data HelloID has sent
if ($emailBusinessUpdated -eq $true) {
    $result.ExportData | Add-Member -MemberType NoteProperty -Name BusinessEmailAddress -Value $($account.AfasEmployee.Element.Objects[0].KnPerson.Element.Fields.EmAd) -Force
}
if ($emailPortalUpdated -eq $true) {
    $result.ExportData | Add-Member -MemberType NoteProperty -Name PortalEmailAddress -Value $($account.AfasEmployee.Element.Objects[0].KnPerson.Element.Fields.EmailPortal) -Force
}
if ($telephoneNumberUpdated -eq $true) {
    $result.ExportData | Add-Member -MemberType NoteProperty -Name TelephoneNumber -Value $($account.AfasEmployee.Element.Objects[0].KnPerson.Element.Fields.TeNr) -Force
}
if ($mobileUpdated -eq $true) {
    $result.ExportData | Add-Member -MemberType NoteProperty -Name MobileNumber -Value $($account.AfasEmployee.Element.Objects[0].KnPerson.Element.Fields.MbNr) -Force
}
Write-Output $result | ConvertTo-Json -Depth 10