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

    #Correlate on Gebruiker field because thats the accountreference of the system
    $CorrelationField = 'Medewerker'

    $CorrelationRequestLog = "`"$($CorrelationField) -eq '$($actionContext.References.Account)'`""

    #Query employee record
    $GetEmployeeRequest = @{
        Uri    = Format-TargetURL -Uri $ConnectorBaseUri -Endpoint $ActionContext.Configuration.GETConnector
        Method = 'GET'
        Body = @{
            filterfieldids = $CorrelationField
            filtervalues   = $ActionContext.References.Account
            operatortypes  = 1
        }
    }

    $AFASEmployeeRows = (Invoke-RestMethod @AFASRequests @GetEmployeeRequest).rows

    #Handle retrieved entries
    if ($AFASEmployeeRows.count -eq 0) {
        Throw "Could not find employee record in GET-Connector '$($ActionContext.Configuration.GETConnector)' based on correlation request $($CorrelationRequestLog)"
    }
    elseif ($AFASEmployeeRows.Count -gt 1) {
        Throw "Retrieved $($AFASEmployeeRows.Count) employee entries in GET-Connector '$($actionContext.Configuration.GETConnector)' based on correlation request $($CorrelationRequestLog)"
    }
    elseif ($actionContext.Data -ne $Null) {
        Write-verbose -verbose "Correlated $($AFASEmployeeRows.Count) employee entry in GET-Connector '$($actionContext.Configuration.GETConnector)' based on correlation request $($CorrelationRequestLog)"
        
        $AFASEmployee = $AFASEmployeeRows | Select-Object -First 1
    
        $ActionContext.Data | Add-Member -Force -MemberType 'NoteProperty' -Name 'BcCo' -Value $AFASEmployee.Persoonsnummer

        if ('Persoonsnummer' -in $ActionContext.Data.PSObject.Properties.Name) {
            $OutputContext.Data.Persoonsnummer = $AFASEmployee.Persoonsnummer
        }

        if ('Medewerker' -in $ActionContext.Data.PSObject.Properties.Name) {
            $OutputContext.Data.Medewerker = $AFASEmployee.Medewerker
        }

        $PreviousData = @{
            EmailPortal = $AFASEmployee.Email_werk_gebruiker
            EmAd        = $AFASEmployee.Email_werk
            TeNr        = $AFASEmployee.Telefoonnr_werk
            MbNr        = $AFASEmployee.Mobielnr_werk
            BcCo        = $AFASEmployee.Persoonsnummer
        }

        $OutputContext.PreviousData | Add-Member -Force -NotePropertyMembers $PreviousData

        #Calculate updateable fields
        $UpdatableFields = $ActionContext.Data.PSObject.Properties.Name | Where-Object {
            $_ -in $PreviousData.GetEnumerator().Name -and
            $_ -notin @(
                'Persoonsnummer'
                'Medewerker'
            )
        }

        if ($Null -ne $UpdatableFields) {
            $Fields = [PSCustomObject]@{
                MatchPer = 0
                BcCo     =  $AFASEmployee.Persoonsnummer
            }

            $ActionContext.Data.PSObject.Properties | Where-Object {
                $_.Name -in $UpdatableFields
            } | ForEach-Object {
                $Fields | Add-Member -Force -MemberType 'NoteProperty' -Name $_.Name -Value $_.Value
            }

            #Splat the KnEmployee creation request
            $PutKnEmployeeRequest = @{
                Uri    = Format-TargetURL -Uri $ConnectorBaseUri -Endpoint 'knEmployee'
                Method = 'PUT'
                Body   = [PSCustomObject]@{
                    AfasEmployee = @{
                        Element = @{
                            Objects = @(
                                @{
                                    KnPerson = @{
                                        Element = [PSCustomObject]@{
                                            Fields = $Fields
                                        }
                                    }
                                }
                            )
                            '@EmId' = $ActionContext.References.Account
                        }
                    }
                }
            }

            #If dryrun is true dont execute, but return logging
            if ($ActionContext.DryRun -eq $false) {
                [void] (Invoke-RestMethod @AFASRequests @PutKnEmployeeRequest)
            }
            else {
                Write-verbose -verbose "Updated KnEmployee: '$($Fields | ConvertTo-Json -Depth 10)' for @EmId: '$($PutKnEmployeeRequest.Body.AfasEmployee.Element.'@EmId')'"
            }

            #Return the dataobject
            $OutputContext.Data.PSObject.Properties | Where-Object {
                $_.Name -in $Fields.PSObject.Properties.Name
            } | ForEach-Object {
                $_.Value = $Fields | Select-Object -ExpandProperty $_.Name
            }

            $OutputContext.AuditLogs.add([PSCustomObject]@{
                    Message = "Updated '$($UpdatableFields -join "', '")' properties for KnEmployee '$($ActionContext.References.Account)' for: '$($personContext.Person.DisplayName)'"
                    IsError = $false
                }
            )
        }
    }

    $outputContext.Success = $true
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
