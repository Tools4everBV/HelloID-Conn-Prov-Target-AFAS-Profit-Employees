$token = "<provide XML token here>"
$baseUri = "https://<Provide Environment Id here>.rest.afas.online/profitrestservices";
$getConnector = "T4E_IAM3_Persons"
$updateConnector = "KnEmployee"

# Enable TLS 1.2
if ([Net.ServicePointManager]::SecurityProtocol -notmatch "Tls12") {
    [Net.ServicePointManager]::SecurityProtocol += [Net.SecurityProtocolType]::Tls12
}

#Initialize default properties
$success = $False;
$p = $person | ConvertFrom-Json;
$aRef = $accountReference | ConvertFrom-Json;
$auditMessage = "Profit identity for person " + $p.DisplayName + " not updated successfully";

$personId = $p.externalId; # Profit Employee Medewerker
$emailaddress = $p.Accounts.MicrosoftAzureAD.mail;
$userPrincipalName = $p.Accounts.MicrosoftAzureAD.userPrincipalName;

try{
    $encodedToken = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($Token))
    $authValue = "AfasToken $encodedToken"
    $Headers = @{ Authorization = $authValue }

    $getUri = $BaseUri + "/connectors/" + $getConnector + "?filterfieldids=Medewerker&filtervalues=$personId"
    $getResponse = Invoke-RestMethod -Method Get -Uri $getUri -ContentType "application/json;charset=utf-8" -Headers $Headers -UseBasicParsing

    #Change mapping here
    $account = [PSCustomObject]@{
        'AfasEmployee' = @{
            'Element' = @{
                '@EmId' = $getResponse.rows.medewerker;
                'Objects' = @(@{
                    'KnPerson' = @{
                        'Element' = @{
                            'Fields' = @{
                                # Zoek op BcCo (Persoons-ID)
                                'MatchPer' = 0;
                                # Nummer
                                'BcCo' = $getResponse.rows.nummer;
                                # E-Mail werk  
                                'EmAd' = $emailaddress;
                                # E-Mail toegang
                                'EmailPortal' = $userPrincipalName;
                            }
                        }
                    }
                })
            }
        }
    }

    if(-Not($dryRun -eq $True)){
        $body = $account | ConvertTo-Json -Depth 10
        $putUri = $BaseUri + "/connectors/" + $updateConnector

        $putResponse = Invoke-RestMethod -Method Put -Uri $putUri -Body $body -ContentType "application/json;charset=utf-8" -Headers $Headers -UseBasicParsing
    }
    $success = $True;
    $auditMessage = " successfully"; 
}catch{
    if(-Not($_.Exception.Response -eq $null)){
        $result = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($result)
        $reader.BaseStream.Position = 0
        $reader.DiscardBufferedData()
        $errResponse = $reader.ReadToEnd();
        $auditMessage = " : ${errResponse}";
    }else {
        $auditMessage = " : General error";
    } 
}

#build up result
$result = [PSCustomObject]@{
    Success= $success;
    AccountReference= $aRef;
    AuditDetails=$auditMessage;
    Account= $account;
};
    
Write-Output $result | ConvertTo-Json -Depth 10;