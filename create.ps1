#region functions
Function Format-TargetURL {
    [CmdletBinding(DefaultParameterSetName = 'String')]
    [OutputType([System.Uri])]
    param (
        [Parameter(Mandatory, ParameterSetName = 'String', Position = 0)]
        [String]
        $Url,

        [Parameter(Mandatory, ParameterSetName = 'Uri', Position = 0)]
        [System.Uri]
        $Uri,

        [Parameter(Position = 1)]
        [String]
        $Endpoint
    )

    if ($PsCmdlet.ParameterSetName -eq 'String') {
        $Uri = $Null
        
        if ([System.Uri]::TryCreate($Url, 'RelativeOrAbsolute', [ref]$Uri)) {
            if ([String]::IsNullOrEmpty($Uri.Scheme)) {
                $Uri = [System.Uri]::new(
                    "https://$($Uri.OriginalString)"
                )
            }
        }
        else {
            Throw "Invalid URL configured: '$($Url)'"
        }
    }

    if (-not [String]::IsNullOrEmpty($Endpoint)) {
        $PathSegment = @(
            $Uri.AbsolutePath.TrimEnd('/')
            $EndPoint.TrimStart('/')
        ) -join '/'

        $Uri = [System.Uri]::new(
            $Uri,
            $PathSegment
        )
    }

    return $Uri
}
#endregion functions

#region script
try {    
    # Set TLS to accept TLS 1.2
    [Net.ServicePointManager]::SecurityProtocol = @(
        [Net.SecurityProtocolType]::Tls12
    )

    $EncodedToken = [System.Convert]::ToBase64String(
        [System.Text.Encoding]::ASCII.GetBytes($ActionContext.Configuration.Token)
    )

    #Build Base AFAS request splattable object
    $AFASRequests = @{
        ContentType     = "application/json;charset=utf-8"
        Headers         = @{
            Authorization = "AfasToken $($EncodedToken)"
        }
    }

    #BaseUri to execute requests with connectors
    $ConnectorBaseUri = Format-TargetURL -Url $ActionContext.Configuration.BaseUri -Endpoint 'connectors'

    # Validate correlation configuration
    if ($ActionContext.CorrelationConfiguration.Enabled -eq $true) {
        #Check for correct correlation configuration (account field should be configured)
        if ($Null -eq $ActionContext.CorrelationConfiguration.AccountField) {
            throw 'Correlation is enabled but not configured correctly because the Account Correlation Field is empty'
        }

        $correlationField = $ActionContext.CorrelationConfiguration.AccountField

        #Check for correct correlation configuration (person field should be configured)
        if ($Null -eq $ActionContext.CorrelationConfiguration.PersonField) {
            throw 'Correlation is enabled but not configured correctly because the Person Correlation Field is empty'
        }

        $correlationValue = $ActionContext.CorrelationConfiguration.PersonFieldValue

        #If the correlationValue is empty throw an error
        if ([string]::IsNullOrEmpty($CorrelationValue)) {
            throw 'Correlation is enabled but the correlation value is empty'
        }

        $CorrelationRequestLog = "`"$($ActionContext.CorrelationConfiguration.AccountField) -eq '$($correlationValue)'`""

        #Query employee record
        $GetEmployeeRequest = @{
            Uri    = Format-TargetURL -Uri $ConnectorBaseUri -Endpoint $ActionContext.Configuration.GETConnector
            Method = 'GET'
            Body = @{
                filterfieldids = $ActionContext.CorrelationConfiguration.AccountField
                filtervalues   = $correlationValue
                operatortypes  = 1
            }
        }

        $AFASEmployeeRows = (Invoke-RestMethod @AFASRequests @GetEmployeeRequest).Rows

        #Handle retrieved entries
        if ($AFASEmployeeRows.count -eq 0) {
            Throw "Could not find employee record in GET-Connector '$($ActionContext.Configuration.GETConnector)' based on correlation request $($CorrelationRequestLog)"
        }
        elseif ($AFASEmployeeRows.Count -gt 1) {
            Throw "Retrieved $($AFASEmployeeRows.Count) employee entries in GET-Connector '$($actionContext.Configuration.GETConnector)' based on correlation request $($CorrelationRequestLog)"
        }
        else {
            Write-verbose -verbose "Correlated $($AFASEmployeeRows.Count) employee entry in GET-Connector '$($actionContext.Configuration.GETConnector)' based on correlation request $($CorrelationRequestLog)"
            
            $AFASEmployee = $AFASEmployeeRows | Select-Object -First 1

            #Required in all requests for the employee
            $ActionContext.Data | Add-Member -Force -MemberType 'NoteProperty' -Name 'BcCo' -Value $AFASEmployee.Persoonsnummer

            $OutputContext.Data.Persoonsnummer = $AFASEmployee.Persoonsnummer
            $OutputContext.Data.Medewerker     = $AFASEmployee.Medewerker

            $OutputContext.PreviousData = [PSCustomObject]@{
                EmailPortal    = $AFASEmployee.Email_werk_gebruiker
                EmAd           = $AFASEmployee.UPN
                TeNr           = $AFASEmployee.Profit_Windows
                MbNr           = $AFASEmployee.Connector
                BcCo           = $AFASEmployee.Persoonsnummer
                Medewerker     = $AFASEmployee.Persoonsnummer
                Persoonsnummer = $AFASEmployee.Medewerker
            }
            
            #Set account reference and correlation status
            $OutputContext.AccountReference = $AFASEmployee.Medewerker
            $OutputContext.AccountCorrelated = $true

            $OutputContext.AuditLogs.Add(
                [PSCustomObject]@{
                    Action  = 'CorrelateAccount'
                    Message = "Correlated KnEmployee '$($OutputContext.AccountReference)' on filter: $($CorrelationRequestLog)"
                    IsError = $False
                }
            )
        }
    }
    elseif ($ActionContext.CorrelationConfiguration.Enabled -eq $false) {
        #There needs to be an employee correlated for this target system to work
        Throw 'Correlation is disabled, but correlation is required for this target system'
    }

    $OutputContext.Success = $True
}
catch {
    $OutputContext.AuditLogs.add([PSCustomObject]@{
            Message = "An exception occured while processing account for '$($PersonContext.Person.DisplayName)': '$($_.Exception.message)'"
            IsError = $true
        }
    )
        
    Write-Warning $_.Exception.message
}
#endregion script
