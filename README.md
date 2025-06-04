
# HelloID-Conn-Prov-Target-AFAS-Profit-Employees

> [!IMPORTANT]
> This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.

<p align="center">
  <img src="https://raw.githubusercontent.com/Tools4everBV/HelloID-Conn-Prov-Target-AFAS-Profit-Employees/refs/heads/main/Logo.png">
</p>

## Table of contents

- [HelloID-Conn-Prov-Target-AFAS-Profit-Employees](#helloid-conn-prov-target-afas-profit-employees)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Getting started](#getting-started)
    - [Provisioning PowerShell V2 connector](#provisioning-powershell-v2-connector)
      - [Correlation configuration](#correlation-configuration)
      - [Field mapping](#field-mapping)
    - [Connection settings](#connection-settings)
    - [Prerequisites](#prerequisites)
    - [Remarks](#remarks)
      - [Scope](#scope)
  - [Setup the connector](#setup-the-connector)
    - [Updating a custom field for AFAS employee](#updating-a-custom-field-for-afas-employee)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Target-AFAS-Profit-Employees is a _target_ connector. _AFAS-Profit-Employees_ provides a interface to communicate with Profit through a set of GetConnectors, which is component that allows the creation of custom views on the Profit data. GetConnectors are based on a pre-defined 'data collection', which is an existing view based on the data inside the Profit database. 

| Endpoint                      | Description |
| ----------------------------- | ----------- |
| profitrestservices/connectors |             |

The following lifecycle actions are available:

| Action             | Description                                                                                                     |
| ------------------ | --------------------------------------------------------------------------------------------------------------- |
| create.ps1         | PowerShell _correlate_ lifecycle action. Correlates                                                             |
| delete.ps1         | PowerShell _delete_ lifecycle action. Update on correlate and update on update                                  |
| update.ps1         | PowerShell _update_ lifecycle action. Clear the unique fields, since the values have to be unique over all AFAS |
| configuration.json | Default _configuration.json_                                                                                    |
| fieldMapping.json  | Default _fieldMapping.json_                                                                                     |

## Getting started

By using this connector you will have the ability to update employees in the AFAS Profit system.

Connecting to Profit is done using the app connector system. 
Please see the following pages from the AFAS Knowledge Base for more information.

[Create the APP connector](https://help.afas.nl/help/NL/SE/App_Apps_Custom_Add.htm)

[Manage the APP connector](https://help.afas.nl/help/NL/SE/App_Apps_Custom_Maint.htm)

[Manual add a token to the APP connector](https://help.afas.nl/help/NL/SE/App_Apps_Custom_Tokens_Manual.htm)

### Provisioning PowerShell V2 connector

#### Correlation configuration

The correlation configuration is used to specify which properties will be used to match an existing account within _{connectorName}_ to a person in _HelloID_.

To properly setup the correlation:

1. Open the `Correlation` tab.

2. Specify the following configuration:

    | Setting                   | Value        |
    | ------------------------- | ------------ |
    | Enable correlation        | `True`       |
    | Person correlation field  | ``           |
    | Account correlation field | `Medewerker` |

> [!TIP]
> _For more information on correlation, please refer to our correlation [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems/correlation.html) pages_.

#### Field mapping

The field mapping can be imported by using the [_fieldMapping.json_](./fieldMapping.json) file.

> [!TIP]
> `EmailPortal`, `TeNr` and `MbNr` are fields that can be mapped. Typically these are not fields that HelloID Provisioning needs to write back.

### Connection settings

The following settings are required to connect to the API.

| Setting                       | Description                                                                                                                                           | Mandatory |
| ----------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- | --------- |
| Base Uri                      | The URL to the AFAS environment REST services                                                                                                         | Yes       |
| Token in XML format           | The AppConnector token to connect to AFAS                                                                                                             | Yes       |
| Get Connector                 | The GetConnector in AFAS to query the employee with                                                                                                   | Yes       |
| Update Connector              | The UpdateConnector in AFAS to update the employee with                                                                                               | Yes       |
| Create account when not found | When toggled, if the employee account is not found, a new the AFAS employee account will be created in the create action (only in the create action). |           |
| Update on update              | When toggled, if the mapped data differs from data in AFAS, the AFAS employee will be updated when a update is triggerd.                              |           |
| Toggle debug logging          | When toggled, extra logging is shown. Note that this is only meant for debugging, please switch this off when in production.                          |           |

### Prerequisites

- [ ] HelloID Provisioning agent (cloud or on-prem).
- [ ] Loaded and available AFAS GetConnectors.
- [ ] In addition to use to the above get-connector, the connector also uses the following build-in Profit update-connectors:
*	KnEmployee
- [ ] AFAS App Connector with access to the GetConnectors and associated views.
  - [ ] Token for this AppConnector

> [!TIP]
> For this connector we have created a default set [Tools4ever - HelloID - T4E_HelloID_Users_v2.gcn], which can be imported directly into the AFAS Profit environment.

> [!NOTE]
> When the connector is defined as target system, only the following GetConnector is used by HelloID:
> * 	Tools4ever - HelloID - T4E_HelloID_Users_v2

### Remarks

> [!IMPORTANT]
> In view of GDPR, the persons private data, such as private email address and birthdate are not in the data collection by default. When needed for the implementation (e.g. set emailaddress with private email address on delete), these properties will have to be added.

> [!IMPORTANT]
> We never delete employees in AFAS, we only clear the unique fields.

#### Scope
The data collection retrieved by the set of GetConnector's is sufficient for HelloID to provision persons.
The data collection can be changed by the customer itself to meet their requirements.

| Connector                                       | Field               | Default filter            |
| ----------------------------------------------- | ------------------- | ------------------------- |
| __Tools4ever - HelloID - T4E_HelloID_Users_v2__ | contract start date | <[Vandaag + 3 maanden]    |
|                                                 | contract end date   | >[Vandaag - 3 maanden];[] |



## Setup the connector

> [!TIP]
> `EmailPortal` is typically set on the AFAS user. We have a separate [target connector](https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-AFAS-Profit-Users) for managing AFAS users 

### Updating a custom field for AFAS employee
In certain situations, you want to write certain information back to a custom field in AFAS. The example below explains how to add this to the code.

For more information about updating a custom field for AFAS employees. Please check the [AFAS documentation](https://help.afas.nl/help/NL/SE/App_Cnnctr_Update_050.htms)

If you want to compare the custom field with your field mapping. The custom field needs to be added to the `T4E_HelloID_Users_v2` GetConnector,

```powershell
$updateAccount = [PSCustomObject]@{
    'AfasEmployee' = @{
        'Element' = @{
            '@EmId'   = $currentAccount.Medewerker
            'Fields'  = @{ 
                '<YOUR GUID / UUID CODE FROM AFAS>' = $account.fieldNameAFAS
            }
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
```
> [!NOTE]
> Because mapped values are typically added in the body of 'KnPerson' you need to skip the `$account.fieldNameAFAS` from adding it to the `$AfasEmployee` body. Also, you need to add the field to `$updateAccountFields` and `$previousAccount`. Example:

```powershell
$updateAccountFields = @()
if ($account.PSObject.Properties.Name -Contains 'fieldNameAFAS') {
    $updateAccountFields += "fieldNameAFAS"
}
```

```powershell
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
    # Overtime
    'fieldNameAFAS'    = $currentAccount.Overtime
}
```

```powershell
foreach ($newProperty in $newProperties ) {
    if ($newProperty.name -ne 'fieldNameAFAS') {
        $updateAccount.AfasEmployee.Element.Objects[0].KnPerson.Element.Fields.$($newProperty.Name) = $newProperty.Value
    }                 
}
```



> [!TIP]
> If you need more information please check out our [forum post](https://forum.helloid.com/forum/helloid-provisioning/1261-updating-a-custom-field-for-afas-employee).

## Getting help

> [!TIP]
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages_.

> [!TIP]
>  _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_.

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
