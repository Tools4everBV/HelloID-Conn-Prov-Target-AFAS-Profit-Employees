$config = ConvertFrom-Json $configuration

$BaseUri = $config.BaseUri
$Token = $config.Token
$getConnector = "T4E_HelloID_Users"
$updateConnector = "KnEmployee"

#Initialize default properties
$p = $person | ConvertFrom-Json;
$m = $manager | ConvertFrom-Json;
$aRef = $accountReference | ConvertFrom-Json;
$mRef = $managerAccountReference | ConvertFrom-Json;
$success = $False;
$auditLogs = New-Object Collections.Generic.List[PSCustomObject];

# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

$filterfieldid = "Persoonsnummer"
$filtervalue = $p.externalId; # Has to match the AFAS value of the specified filter field ($filterfieldid)
$emailaddress = $p.Accounts.MicrosoftActiveDirectory.mail;
$userPrincipalName = $p.Accounts.MicrosoftActiveDirectory.userPrincipalName;
# $telephoneNumber = $p.Accounts.MicrosoftActiveDirectory.telephoneNumber;
# $mobile = $p.Accounts.MicrosoftActiveDirectory.mobile;

$EmAdUpdated = $false
$EmailPortalUpdated = $false

try{
    $encodedToken = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($Token))
    $authValue = "AfasToken $encodedToken"
    $Headers = @{ Authorization = $authValue }
    $getUri = $BaseUri + "/connectors/" + $getConnector + "?filterfieldids=$filterfieldid&filtervalues=$filtervalue&operatortypes=1"
    $getResponse = Invoke-RestMethod -Method Get -Uri $getUri -ContentType "application/json;charset=utf-8" -Headers $Headers -UseBasicParsing

    if($getResponse.rows.Count -eq 1){
        # Retrieve current account data for properties to be updated
        $previousAccount = [PSCustomObject]@{
            'AfasEmployee' = @{
                    'Element' = @{
                        '@EmId' = $getResponse.rows.Medewerker;
                        'Objects' = @(@{
                            'KnPerson' = @{
                                'Element' = @{
                                    'Fields' = @{
                                        # E-Mail werk  
                                        'EmAd' = $getResponse.rows.Email_werk;
                                  
                                        # phone.business.fixed
                                        'TeNr' = $getResponse.rows.Telefoonnr_werk;
                                        # phone.business.mobile
                                        'MbNr' = $getResponse.rows.Mobielnr_werk;  
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
                    '@EmId' = $getResponse.rows.Medewerker;
                    'Objects' = @(@{
                        'KnPerson' = @{
                            'Element' = @{
                                'Fields' = @{
                                    # Zoek op BcCo (Persoons-ID)
                                    'MatchPer' = 0;
                                    # Nummer
                                    'BcCo' = $getResponse.rows.Persoonsnummer;

                                    # E-Mail toegang - Check with AFAS Administrator if this needs to be set
                                    # 'EmailPortal' = $userPrincipalName;

                                    <#
                                    # phone.business.fixed
                                    'TeNr' = $telephoneNumber;
                                    # phone.business.mobile
                                    'MbNr' = $mobile;
                                    #>    
                                }
                            }
                        }
                    })
                }
            }
        }
        # Set variable to indicate update of EmailPortal has occurred (for export data object)
        # $EmailPortalUpdated = $true

        # If '$emailAdddres' does not match current 'EmAd', add 'EmAd' to update body. AFAS will throw an error when trying to update this with the same value
        if( $getResponse.rows.Email_werk -ne $emailaddress -and -not[string]::IsNullOrEmpty($emailaddress) ){
            # E-mail werk
            $account.'AfasEmployee'.'Element'.Objects[0].'KnPerson'.'Element'.'Fields' += @{'EmAd' = $emailaddress}
            Write-Verbose -Verbose "Updating BusinessEmailAddress '$($getResponse.rows.Email_werk)' with new value '$emailaddress'"
            # Set variable to indicate update of EmAd has occurred (for export data object)
            $EmAdUpdated = $true
        }   

        # Set aRef object for use in futher actions
        $aRef = [PSCustomObject]@{
            Medewerker = $getResponse.rows.Medewerker
            Persoonsnummer = $getResponse.rows.Persoonsnummer
        }

        if(-Not($dryRun -eq $True)){
            $body = $account | ConvertTo-Json -Depth 10

            $putUri = $BaseUri + "/connectors/" + $updateConnector
            $putResponse = Invoke-RestMethod -Method Put -Uri $putUri -Body $body -ContentType "application/json;charset=utf-8" -Headers $Headers -UseBasicParsing
        }

        $auditLogs.Add([PSCustomObject]@{
            Action = "CreateAccount"
            Message = "Correlated to and updated fields of account with id $($aRef.Medewerker)"
            IsError = $false;
        });

        $success = $true;       
    }
}catch{
    $auditLogs.Add([PSCustomObject]@{
        Action = "CreateAccount"
        Message = "Error correlating and updating fields of account with Id $($aRef.Medewerker): $($_)"
        IsError = $True
    });
    Write-Warning $_;
}

# Send results
$result = [PSCustomObject]@{
	Success= $success;
	AccountReference= $aRef;
	AuditLogs = $auditLogs;
    Account = $account;
    PreviousAccount = $previousAccount;    

    # Optionally return data for use in other systems
    ExportData       = [PSCustomObject]@{
        Medewerker      = $aRef.Medewerker
        Persoonsnummer  = $aRef.Persoonsnummer      
    };    
};

# Only add the data to ExportData if it has actually been updated, since we want to store the data HelloID has sent
if($EmAdUpdated -eq $true){
    $result.ExportData | Add-Member -MemberType NoteProperty -Name BusinessEmailAddress -Value $($account.AfasEmployee.Element.Objects[0].KnPerson.Element.Fields.EmAd) -Value "EmAd" -Force
}
if($EmailPortalUpdated -eq $true){
    $result.ExportData | Add-Member -MemberType NoteProperty -Name PortalEmailAddress -Value $($account.AfasEmployee.Element.Objects[0].KnPerson.Element.Fields.EmailPortal) -Force
}
Write-Output $result | ConvertTo-Json -Depth 10;