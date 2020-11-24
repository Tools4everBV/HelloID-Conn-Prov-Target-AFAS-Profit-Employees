$config = ConvertFrom-Json $configuration

$BaseUri = $config.BaseUri
$Token = $config.Token
$getConnector = "T4E_HelloID_Users"
$updateConnector = "KnEmployee"

# Enable TLS 1.2
if ([Net.ServicePointManager]::SecurityProtocol -notmatch "Tls12") {
    [Net.ServicePointManager]::SecurityProtocol += [Net.SecurityProtocolType]::Tls12
}

#Initialize default properties
$success = $False;
$p = $person | ConvertFrom-Json;
$auditMessage = "Profit identity for person " + $p.DisplayName + " not updated successfully";

$personId = $p.externalId; # Profit Employee Medewerker
$emailaddress = $p.Accounts.MicrosoftActiveDirectory.userPrincipalName;
$userPrincipalName = $p.Accounts.MicrosoftActiveDirectory.userPrincipalName;
# $telephoneNumber = $p.Accounts.MicrosoftActiveDirectory.telephoneNumber;
# $mobile = $p.Accounts.MicrosoftActiveDirectory.mobile;

try{
    $encodedToken = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($Token))
    $authValue = "AfasToken $encodedToken"
    $Headers = @{ Authorization = $authValue }
    $getUri = $BaseUri + "/connectors/" + $getConnector + "?filterfieldids=Nummer&filtervalues=$personId"
    $getResponse = Invoke-RestMethod -Method Get -Uri $getUri -ContentType "application/json;charset=utf-8" -Headers $Headers -UseBasicParsing
    
    if($getResponse.rows.Count -eq 1){
        #Change mapping here
        # If 'EmailPortal' matches 'Email_werk_gebruiker', skip 'EmailPortal' in update body. AFAS will throw an error when trying to update this with the same value
        if($getResponse.rows.Email_werk_gebruiker -eq $userPrincipalName){
            # Update without 'EmailPortal'
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

                                        # E-Mail werk  
                                        'EmAd' = $emailaddress;

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
        }else{
            # Update with 'EmailPortal'
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

                                        # E-Mail werk  
                                        'EmAd' = $emailaddress;
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
        }
        if(-Not($dryRun -eq $True)){
            $body = $account | ConvertTo-Json -Depth 10
            Write-Verbose $body
            $putUri = $BaseUri + "/connectors/" + $updateConnector
            $putResponse = Invoke-RestMethod -Method Put -Uri $putUri -Body $body -ContentType "application/json;charset=utf-8" -Headers $Headers -UseBasicParsing
            $aRef = $($account.AfasEmployee.Values.'@EmId')
        }
        $success = $True;
        $auditMessage = " $($account.AfasEmployee.Values.'@EmId') successfully";
    }
}catch{
    $errResponse = $_;
    $auditMessage = " $($account.AfasEmployee.Values.'@EmId') : ${errResponse}";
}

#build up result
$result = [PSCustomObject]@{
    Success= $success;
    AccountReference= $aRef;
    AuditDetails=$auditMessage;
    Account= $account;
};
    
Write-Output $result | ConvertTo-Json -Depth 10;