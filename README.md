# HelloID-Conn-Prov-Target-AFAS-Profit-Employees
Repository for HelloID Provisioning Target Connector to AFAS Employees

<a href="https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-AFAS-Profit-Employees/network/members"><img src="https://img.shields.io/github/forks/Tools4everBV/HelloID-Conn-Prov-Target-AFAS-Profit-Employees" alt="Forks Badge"/></a>
<a href="https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-AFAS-Profit-Employees/pulls"><img src="https://img.shields.io/github/issues-pr/Tools4everBV/HelloID-Conn-Prov-Target-AFAS-Profit-Employees" alt="Pull Requests Badge"/></a>
<a href="https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-AFAS-Profit-Employees/issues"><img src="https://img.shields.io/github/issues/Tools4everBV/HelloID-Conn-Prov-Target-AFAS-Profit-Employees" alt="Issues Badge"/></a>
<a href="https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-AFAS-Profit-Employees/graphs/contributors"><img alt="GitHub contributors" src="https://img.shields.io/github/contributors/Tools4everBV/HelloID-Conn-Prov-Target-AFAS-Profit-Employees?color=2b9348"></a>

| :warning: Warning |
| :---------------- |
| This script is for the new powershell connector. Make sure to use the mapping and correlation keys like mentionded in this readme. For more information, please read our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) |


| :information_source: Information |
|:---------------------------|
| This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.       |
<br />
<p align="center">
  <img src="https://www.tools4ever.nl/connector-logos/afas-logo.png">
</p>

<!-- TABLE OF CONTENTS -->
## Table of Contents
- [HelloID-Conn-Prov-Target-AFAS-Profit-Employees](#helloid-conn-prov-target-afas-profit-employees)
  - [Table of Contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Getting Started](#getting-started)
    - [Connection settings](#connection-settings)
    - [Prerequisites](#prerequisites)
    - [GetConnector](#getconnector)
      - [Remarks](#remarks)
      - [Scope](#scope)
    - [UpdateConnector](#updateconnector)
    - [Mapping](#mapping)
    - [Correlation](#correlation)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)


## Introduction
The interface to communicate with Profit is through a set of GetConnectors, which is component that allows the creation of custom views on the Profit data. GetConnectors are based on a pre-defined 'data collection', which is an existing view based on the data inside the Profit database. 

For this connector we have created a default set, which can be imported directly into the AFAS Profit environment.
The HelloID connector consists of the template scripts shown in the following table.

| Action                          | Action(s) Performed   | Comment   | 
| ------------------------------- | --------------------- | --------- |
| create.ps1                      | Update AFAS employee  | Correlates AFAS employee |
| update.ps1                      | Update AFAS employee  | Update on correlate and update on update |
| delete.ps1                      | Update AFAS employee  | Clear the unique fields, since the values have to be unique over all AFAS environments |

<!-- GETTING STARTED -->
## Getting Started

By using this connector you will have the ability to retrieve employee and contract data from the AFAS Profit HR system.

Connecting to Profit is done using the app connector system. 
Please see the following pages from the AFAS Knowledge Base for more information.

[Create the APP connector](https://help.afas.nl/help/NL/SE/App_Apps_Custom_Add.htm)

[Manage the APP connector](https://help.afas.nl/help/NL/SE/App_Apps_Custom_Maint.htm)

[Manual add a token to the APP connector](https://help.afas.nl/help/NL/SE/App_Apps_Custom_Tokens_Manual.htm)

### Connection settings

The following settings are required to connect to the API.

| Setting                     | Description  | Mandatory |
| --------------------------- | -----------  | --------- |
| Base Uri                    | The URL to the AFAS environment REST services  | Yes       |
| Token in XML format         | The AppConnector token to connect to AFAS  | Yes       |
| Get Connector               | The GetConnector in AFAS to query the user with  | Yes       |
| Update Connector            | The UpdateConnector in AFAS to update the user with  | Yes       |
| Update on update         | When toggled, if the mapped data differs from data in AFAS, the AFAS user will be updated when a update is triggerd. | No        |
| Toggle debug logging        | When toggled, extra logging is shown. Note that this is only meant for debugging, please switch this off when in production.                                  | No        |

### Prerequisites

- [ ] HelloID Provisioning agent (cloud or on-prem).
- [ ] Loaded and available AFAS GetConnectors.
- [ ] AFAS App Connector with access to the GetConnectors and associated views.
  - [ ] Token for this AppConnector

### GetConnector
When the connector is defined as target system, only the following GetConnector is used by HelloID:

* Tools4ever - HelloID - T4E_HelloID_Users_v2

#### Remarks
 - In view of GDPR, the persons private data, such as private email address and birthdate are not in the data collection by default. When needed for the implementation (e.g. set emailaddress with private email address on delete), these properties will have to be added.

#### Scope
The data collection retrieved by the set of GetConnector's is sufficient for HelloID to provision persons.
The data collection can be changed by the customer itself to meet their requirements.

| Connector                                             | Field               | Default filter            |
| ----------------------------------------------------- | ------------------- | ------------------------- |
| __Tools4ever - HelloID - T4E_HelloID_Users_v2__       | contract start date | <[Vandaag + 3 maanden]    |
|                                                       | contract end date   | >[Vandaag - 3 maanden];[] |

### UpdateConnector
In addition to use to the above get-connector, the connector also uses the following build-in Profit update-connectors:

* knEmployee

### Mapping
The mandatory and recommended field mapping is listed below.

| Name           | Create | Enable | Update | Disable | Delete | Store in account data | Default mapping                            | Mandatory | Comment                                        |
| -------------- | ------ | ------ | ------ | ------- | ------ | --------------------- | ------------------------------------------ | --------- | ---------------------------------------------- |
| Medewerker     | X      |        | X      |         |        | Yes                   | Field: ExternalId                          | Yes       | Used for Correlation and to store account data |
| Persoonsnummer | X      |        | X      |         |        | Yes                   | None                                       | Yes       | Used to store account data                     |
| EmAd           |        |        | X      |         | X      | Yes                   | Update: Complex EmAd.js Delete Fixed empty |           | E-Mail werk                                    |

The fields listed below are examples of available fields for mapping but are typically not used.

| Name        | Create | Enable | Update | Disable | Delete | Store in account data | Default mapping                        | Mandatory | Comment                                                                |
| ----------- | ------ | ------ | ------ | ------- | ------ | --------------------- | -------------------------------------- | --------- | ---------------------------------------------------------------------- |
| EmailPortal |        |        | X      |         | X      | Yes                   | <Your preferred value> for example UPN |           | E-mail toegang - Check with AFAS Administrator if this needs to be set |
| TeNr        |        |        | X      |         | X      | Yes                   | <Your preferred value>                 |           | Telefoonnr. werk                                                       |
| MbNr        |        |        | X      |         | X      | Yes                   | <Your preferred value>                 |           | Mobiel werk                                                            |


### Correlation
It is mandatory to enable the correlation in the correlation tab. The default value for "person correlation field" is " ExternalId". The default value for "Account Correlation field" is "Medewerker".


## Getting help
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/hc/en-us/articles/360012558020-Configure-a-custom-PowerShell-target-system) pages_

> _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_

## HelloID docs
The official HelloID documentation can be found at: https://docs.helloid.com/
