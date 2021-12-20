#region Config
$Config = $Configuration | ConvertFrom-Json

$BaseUri = $Config.BaseUri.TrimEnd('/')
$Token = $Config.Token

$GetConnector = "T4E_HelloID_Users"
$UpdateConnector = "KnEmployee"
#endregion Config

#region default properties
#$p = $person | ConvertFrom-Json
#$m = $manager | ConvertFrom-Json

$aRef = $AccountReference | ConvertFrom-Json
#$mRef = $managerAccountReference | ConvertFrom-Json

$Success = $False
$AuditLogs = [Collections.Generic.List[PSCustomObject]]::new()
#endregion default properties

$FilterfieldName = $Config.FilterfieldName
$FilterValue = $aRef.$FilterfieldName # Has to match the AFAS value of the specified filter field ($FilterfieldName)

# Set TLS to accept TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = @(
    [Net.SecurityProtocolType]::Tls11
    [Net.SecurityProtocolType]::Tls12
)

# The new account variables
$Account = @{
    # E-Mail toegang - Check with AFAS Administrator if this needs to be set
    'EmailPortal' = "$($aRef.Persoonsnummer)@domain.com" # Unique value based of PersonId because at the revoke action we want to clear the unique fields

    # E-Mail werk
    'EmAd' = "$($aRef.Persoonsnummer)@domain.com" # Unique value based of PersonId because at the revoke action we want to clear the unique fields

    # phone.business.fixed
    # 'TeNr' = $p.Accounts.MicrosoftActiveDirectory.telephoneNumber

    # phone.business.mobile
    # 'MbNr' = $p.Accounts.MicrosoftActiveDirectory.mobile
}

# Start Script
try {
    $EncodedToken = [System.Convert]::ToBase64String(
        [System.Text.Encoding]::ASCII.GetBytes($Token))

    $RestMethod = @{
        UseBasicParsing = $True
        ContentType = "application/json;charset=utf-8"
        Headers = @{
            Authorization = "AfasToken $($EncodedToken)"
        }
    }

    # Fetch Employee from AFAS
    $Uri = "$($BaseUri)/connectors/$($GetConnector)"

    $AFASEmployee = Invoke-RestMethod @RestMethod -Method Get -Uri $Uri -Body @{
        filterfieldids = $FilterfieldName
        filtervalues   = $FilterValue
        operatortypes  = 1
    } | Select-Object -ExpandProperty 'rows'

    # Validating that we only get one user
    if ($AFASEmployee.Count -eq 0) {
        throw "No user found where field '$FilterfieldName' has value '$FilterValue'"
    }

    if ($AFASEmployee.Count -ge 2) {
        throw "Multiple users found where field '$FilterfieldName' has value '$FilterValue'"
    }

    # Retrieve current account data for properties to be updated
    $PreviousAccount = @{
        # E-Mail toegang
        'EmailPortal' = $AFASEmployee.Email_werk_gebruiker
        # E-Mail werk
        'EmAd' = $AFASEmployee.Email_werk
        # phone.business.fixed
        'TeNr' = $AFASEmployee.Telefoonnr_werk
        # phone.business.mobile
        'MbNr' = $AFASEmployee.Mobielnr_werk
        # Zoeknaam
        'SeNm' = ''
        # Fax werk
        'FaNr' = ''
    }

    # Fill the UpdatedFields with all changed values
    $UpdatedFields = @{}

    foreach ($Key in $Account.Keys.Clone()) {
        # Make sure all the keys in the $Account exits in the $PreviousAccount
        if (-Not $PreviousAccount.ContainsKey($Key)) {
            throw "The previous account doesn't contain the key '$Key', aborting..."
        }

        # Make empty values null in $Account
        if ([string]::IsNullOrWhiteSpace($Account[$Key])) {
            $Account[$Key] = $Null
        }

        if ($PreviousAccount[$Key] -ne $Account[$Key]) {
            $UpdatedFields.Add($Key, $Account[$Key])

            Write-Information "Updating field $($Key) '$($PreviousAccount[$Key])' with new value '$($Account[$Key])'"
        }
    }

    # Only keep the keys defined in the account
    $PreviousAccount = $PreviousAccount | Select-Object -Property ([string[]]$Account.Keys)
    $Account = [PSCustomObject]$Account

    # Only if something changed, we send an update to AFAS.
    if ($UpdatedFields.count -gt 0) {
        Write-Verbose -Verbose "There is something to update"

        # This is the boilerplate for the update, we will fill it with the correct data after.
        $Template = '{"AfasEmployee":{"Element":{"Objects":[{"KnPerson":{"Element":{"Fields":{}}}}],"@EmId":null}}}' | ConvertFrom-Json

        # Set employee ID
        $Template.AfasEmployee.Element.'@EmId' = $AFASEmployee.Medewerker

        # Reference to the KnPerson Fields property
        $Fields = $Template.AfasEmployee.Element.Objects[0].KnPerson.Element.Fields

        # Set the default update properties
        $Fields | Add-Member -NotePropertyMembers @{
            # Zoek op BcCo (Persoons-ID)
            'MatchPer' = 0
            # Persoons-ID
            'BcCo' = $AFASEmployee.Persoonsnummer
        }

        # set the updated properties
        $Fields | Add-Member -NotePropertyMembers $UpdatedFields

        if (-Not ($dryRun -eq $True)) {
            $Uri = "$($BaseUri)/connectors/$($UpdateConnector)"
            $Body = $Template | ConvertTo-Json -Depth 10 -Compress

            [void] (Invoke-RestMethod @RestMethod -Method Put -Uri $Uri -Body $Body)
        }
        else {
            # For the dryrun, we dump the body in the verbose logging
            Write-Verbose -Verbose (
                $Template | ConvertTo-Json -Depth 10
            )
        }

        Write-Verbose -Verbose "Updated person"
    }
    else {
        Write-Verbose -Verbose "Nothing to update"
    }

    $PreviousAccount | Add-Member -NotePropertyMembers @{
        Medewerker = $aRef.Medewerker
        Persoonsnummer = $aRef.Persoonsnummer
    }

    $Account | Add-Member -NotePropertyMembers @{
        Medewerker = $AFASEmployee.Medewerker
        Persoonsnummer = $AFASEmployee.Persoonsnummer
    }

    # Set aRef object for use in futher actions
    $aRef = [PSCustomObject]@{
        Medewerker = $AFASEmployee.Medewerker
        Persoonsnummer = $AFASEmployee.Persoonsnummer
    }

    $AuditLogs.Add([PSCustomObject]@{
        Action  = "DeleteAccount"
        Message = "Deleted link and updated fields of account with id $($aRef.Medewerker)"
        IsError = $false
    })

    $Success = $true
}
catch {
    $AuditLogs.Add([PSCustomObject]@{
        Action  = "DeleteAccount"
        Message = "Error deleting link and updating fields of account with Id $($aRef.Medewerker): $($_)"
        IsError = $True
    })
    Write-Warning $_
}

# Send results
$Result = [PSCustomObject]@{
    Success = $Success
    AccountReference = $aRef
    AuditLogs = $AuditLogs
    Account = $Account
    PreviousAccount = $PreviousAccount
}

Write-Output $Result | ConvertTo-Json -Depth 10
