#####################################################
# HelloID-Conn-Prov-Target-AFAS-Profit-Employees-Update
#
# Version: 1.2.0
#####################################################
# Initialize default values
$c = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
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

$filterfieldid = "Medewerker"
$filtervalue = $aRef.Medewerker # Has to match the AFAS value of the specified filter field ($filterfieldid)
$emailBusiness = $p.Accounts.MicrosoftActiveDirectory.mail
# $emailPortal = $p.Accounts.MicrosoftActiveDirectory.userPrincipalName
# $telephoneNumber = $p.Accounts.MicrosoftActiveDirectory.telephoneNumber
# $mobile = $p.Accounts.MicrosoftActiveDirectory.mobile

# Define variables to keep track if value has been updated
$emailBusinessUpdated = $false
$EmailPortalUpdated = $false
$telephoneNumberUpdated = $false
$mobileUpdated = $false

# # Troubleshooting
# $filterfieldid = "Medewerker"
# $filtervalue = "AndreO" # Has to match the AFAS value of the specified filter field ($filterfieldid)
# $emailBusiness = "a.oud@enyoi.org"
# $emailPortal = "Andre.Oud@enyoi.com"
# $telephoneNumber = "0229123456"
# $mobile = "0612345678"
# $dryRun = $false

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

if ($null -ne $currentAccount.Medewerker) {
    try {
        # Retrieve current account data for properties to be updated
        $previousAccount = [PSCustomObject]@{
            'AfasEmployee' = @{
                'Element' = @{
                    '@EmId'   = $currentAccount.Medewerker
                    'Objects' = @(@{
                            'KnPerson' = @{
                                'Element' = @{
                                    'Fields' = @{
                                        # E-Mail werk  
                                        'EmAd'        = $currentAccount.Email_werk

                                        # Email Portal
                                        'EmailPortal' = $currentAccount.Email_portal
                                  
                                        # phone.business.fixed
                                        'TeNr'        = $currentAccount.Telefoonnr_werk
                                        
                                        # phone.business.mobile
                                        'MbNr'        = $currentAccount.Mobielnr_werk
                                    }
                                }
                            }
                        })
                }
            }
        }

        # Map the properties to update
        $account = [PSCustomObject]@{
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

        # If '$emailAdddres' does not match current 'EmAd', add 'EmAd' to update body. AFAS will throw an error when trying to update this with the same value
        if ( $currentAccount.Email_werk -ne $emailBusiness -and -not[string]::IsNullOrEmpty($emailBusiness) ) {
            # E-mail werk
            $account.'AfasEmployee'.'Element'.Objects[0].'KnPerson'.'Element'.'Fields' += @{'EmAd' = $emailBusiness }
            # Set variable to indicate update of EmAd has occurred (for export data object)
            $emailBusinessUpdated = $true
            if (-not($dryRun -eq $true)) {
                Write-Information "Updating BusinessEmailAddress '$($currentAccount.Email_werk)' with new value '$emailBusiness'"
            }
            else {
                Write-Warning "DryRun: Would update BusinessEmailAddress '$($currentAccount.Email_werk)' with new value '$emailBusiness'"
            }
        }

        # ## Example to update Email_portal
        # # If '$emailPortal' does not match current 'EmailPortal', add 'EmailPortal' to update body. AFAS will throw an error when trying to update this with the same value
        # if ( $currentAccount.Email_portal -ne $emailPortal -and -not[string]::IsNullOrEmpty($emailPortal) ) {
        #     # E-Mail toegang - Check with AFAS Administrator if this needs to be set
        #     $account.'AfasEmployee'.'Element'.Objects[0].'KnPerson'.'Element'.'Fields' += @{'EmailPortal' = $emailPortal }
        #     # Set variable to indicate update of EmAd has occurred (for export data object)
        #     $EmailPortalUpdated = $true
        #     if (-not($dryRun -eq $true)) {
        #         Write-Information "Updating EmailPortal '$($currentAccount.Email_portal)' with new value '$emailPortal'"
        #     }
        #     else {
        #         Write-Warning "DryRun: Would update EmailPortal '$($currentAccount.Email_portal)' with new value '$emailPortal'"
        #     }
        # }
        # ## End Example to update Email_portal

        # ## Example to update TeNr
        # # If '$telephoneNumber' does not match current 'TeNr', add 'TeNr' to update body. AFAS will throw an error when trying to update this with the same value
        # if ( $currentAccount.Telefoonnr_werk -ne $telephoneNumber -and -not[string]::IsNullOrEmpty($telephoneNumber) ) {
        #     # E-Mail toegang - Check with AFAS Administrator if this needs to be set
        #     $account.'AfasEmployee'.'Element'.Objects[0].'KnPerson'.'Element'.'Fields' += @{'Telefoonnr_werk' = $telephoneNumber }
        #     # Set variable to indicate update of EmAd has occurred (for export data object)
        #     $telephoneNumberUpdated = $true
        #     if (-not($dryRun -eq $true)) {
        #         Write-Information "Updating TelephoneNumber '$($currentAccount.Telefoonnr_werk)' with new value '$telephoneNumber'"
        #     }
        #     else {
        #         Write-Warning "DryRun: Would update TelephoneNumber '$($currentAccount.Telefoonnr_werk)' with new value '$telephoneNumber'"
        #     }
        # }
        # ## End Example to update TeNr

        # ## Example to update MbNr
        # # If '$mobile' does not match current 'MbNr', add 'MbNr' to update body. AFAS will throw an error when trying to update this with the same value
        # if ( $currentAccount.Mobielnr_werk -ne $mobile -and -not[string]::IsNullOrEmpty($mobile) ) {
        #     # E-Mail toegang - Check with AFAS Administrator if this needs to be set
        #     $account.'AfasEmployee'.'Element'.Objects[0].'KnPerson'.'Element'.'Fields' += @{'MbNr' = $mobile }
        #     # Set variable to indicate update of EmAd has occurred (for export data object)
        #     $mobileUpdated = $true
        #     if (-not($dryRun -eq $true)) {
        #         Write-Information "Updating MobileNumber '$($currentAccount.Mobielnr_werk)' with new value '$mobile'"
        #     }
        #     else {
        #         Write-Warning "DryRun: Would update MobileNumber '$($currentAccount.Mobielnr_werk)' with new value '$mobile'"
        #     }
        # }
        # ## End Example to update MbNr

        $body = ($account | ConvertTo-Json -Depth 10)
    
        $splatWebRequest = @{
            Uri             = $BaseUri + "/connectors/" + $updateConnector
            Headers         = $headers
            Method          = 'PUT'
            Body            = ([System.Text.Encoding]::UTF8.GetBytes($body))
            UseBasicParsing = $true
        }

        if ($true -eq $emailBusinessUpdated -or $true -eq $emailPortalUpdated -or $true -eq $telephoneNumberUpdated -or $true -eq $mobileUpdated) {
            if (-not($dryRun -eq $true)) {
                $updatedAccount = Invoke-RestMethod @splatWebRequest -Verbose:$false

                # Set aRef object for use in futher actions
                $aRef = [PSCustomObject]@{
                    Medewerker     = $currentAccount.Medewerker
                    Persoonsnummer = $currentAccount.Persoonsnummer
                }

                $auditLogs.Add([PSCustomObject]@{
                        Action  = "UpdateAccount"
                        Message = "Successfully updated AFAS employee $($aRef.Medewerker)"
                        IsError = $false
                    })
            }
            else {
                Write-Warning "DryRun: Would update AFAS employee $($aRef.Medewerker)"
            }
        }
        else {
            if (-not($dryRun -eq $true)) {
                # Set aRef object for use in futher actions
                $aRef = [PSCustomObject]@{
                    Medewerker     = $currentAccount.Medewerker
                    Persoonsnummer = $currentAccount.Persoonsnummer
                }

                $auditLogs.Add([PSCustomObject]@{
                        Action  = "UpdateAccount"
                        Message = "Successfully updated AFAS employee $($aRef.Medewerker) (no changes)"
                        IsError = $false
                    })
            }
            else {
                Write-Warning "DryRun: Would update AFAS employee $($aRef.Medewerker) (no changes)"
            }
        }
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
if ($EmailPortalUpdated -eq $true) {
    $result.ExportData | Add-Member -MemberType NoteProperty -Name PortalEmailAddress -Value $($account.AfasEmployee.Element.Objects[0].KnPerson.Element.Fields.EmailPortal) -Force
}
if ($telephoneNumberUpdated -eq $true) {
    $result.ExportData | Add-Member -MemberType NoteProperty -Name TelephoneNumber -Value $($account.AfasEmployee.Element.Objects[0].KnPerson.Element.Fields.TeNr) -Force
}
if ($mobileUpdated -eq $true) {
    $result.ExportData | Add-Member -MemberType NoteProperty -Name MobileNumber -Value $($account.AfasEmployee.Element.Objects[0].KnPerson.Element.Fields.MbNr) -Force
}
Write-Output $result | ConvertTo-Json -Depth 10