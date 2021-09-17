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

$personId = $p.externalId; # Profit Employee Medewerker
$emailaddress = $p.Accounts.AzureADSchoulens.userPrincipalName;
$userPrincipalName = $p.Accounts.AzureADSchoulens.userPrincipalName;
# $telephoneNumber = $p.Accounts.AzureADSchoulens.telephoneNumber;
# $mobile = $p.Accounts.AzureADSchoulens.mobile;

try{
    $encodedToken = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($Token))
    $authValue = "AfasToken $encodedToken"
    $Headers = @{ Authorization = $authValue }
    $getUri = $BaseUri + "/connectors/" + $getConnector + "?filterfieldids=Persoonsnummer&filtervalues=$personId&operatortypes=1"
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

                                    # E-Mail toegang
                                    'EmailPortal' = $userPrincipalName;

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

        # If '$emailAdddres' does not match current 'EmAd', add 'EmAd' to update body. AFAS will throw an error when trying to update this with the same value
        if($getResponse.rows.Email_werk -ne $emailaddress){
            # E-mail werk
            $account.'AfasEmployee'.'Element'.Objects[0].'KnPerson'.'Element'.'Fields' += @{'EmAd' = $emailaddress}
            Write-Verbose -Verbose "Updating BusinessEmailAddress '$($getResponse.rows.Email_werk)' with new value '$emailaddress'"
        }   
        
        if(-Not($dryRun -eq $True)){
            $body = $account | ConvertTo-Json -Depth 10

            $putUri = $BaseUri + "/connectors/" + $updateConnector
            $putResponse = Invoke-RestMethod -Method Put -Uri $putUri -Body $body -ContentType "application/json;charset=utf-8" -Headers $Headers -UseBasicParsing
        }

        $auditLogs.Add([PSCustomObject]@{
            Action = "UpdateAccount"
            Message = "Updated fields of account with id $aRef"
            IsError = $false;
        });

        $success = $true;     
    }
}catch{
    $auditLogs.Add([PSCustomObject]@{
        Action = "UpdateAccount"
        Message = "Error updating fields of account with Id $($aRef): $($_)"
        IsError = $True
    });
	Write-Error $_;
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
        EmployeeId              = $($account.AfasEmployee.Values.'@EmId')
        BusinessEmailAddress    = $($account.AfasEmployee.Element.Objects[0].KnPerson.Element.Fields.EmAd)
        PortalEmailAddress      = $($account.AfasEmployee.Element.Objects[0].KnPerson.Element.Fields.EmailPortal)
    };    
};
Write-Output $result | ConvertTo-Json -Depth 10;
