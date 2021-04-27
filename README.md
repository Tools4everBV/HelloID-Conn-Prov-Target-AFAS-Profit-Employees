# HelloID-Conn-Prov-Target-AFAS-Profit-Employees
<p align="center">
  <img src="https://user-images.githubusercontent.com/68013812/94159371-c1928f80-fe83-11ea-9582-1e4504da8282.png">
</p>

<!-- TABLE OF CONTENTS -->
## Table of Contents
* [Introduction](#introduction)
* [Getting Started](#getting-started)
  * [Source](#source)
  * [Target](#target)
  * [Mappings](#mappings)
  * [Scope](#scope)
* [Setup the PowerShell connector](#setup-the-powershell-connector)


## Introduction
The interface to communicate with Profit is through a set of GetConnectors, which is component that allows the creation of custom views on the Profit data. GetConnectors are based on a pre-defined 'data collection', which is an existing view based on the data inside the Profit database. 

For this connector we have created a default set, which can be imported directly into the AFAS Profit environment.

<!-- GETTING STARTED -->
## Getting Started

By using this connector you will have the ability to update identities from the AFAS Profit HR system.
Since we won't create employees with a target connector the create action is just an update.
Also, because of this, we only have the create and update action, no enable, disable or delete ations.

Connecting to Profit is done using the app connector system. 
Please see the following pages from the AFAS Knowledge Base for more information.

[Create the APP connector](https://help.afas.nl/help/NL/SE/App_Apps_Custom_Add.htm)

[Manage the APP connector](https://help.afas.nl/help/NL/SE/App_Apps_Custom_Maint.htm)

[Manual add a token to the APP connector](https://help.afas.nl/help/NL/SE/App_Apps_Custom_Tokens_Manual.htm)


### Source

The following GetConnectors are required by HelloID when the system is defined as source system: 

*	Tools4ever - HelloID - T4E_HelloID_Employments
*	Tools4ever - HelloID - T4E_HelloID_Positions
*	Tools4ever - HelloID - T4E_HelloID_Groups
*	Tools4ever - HelloID - T4E_HelloID_OrganizationalUnits
*	Tools4ever - HelloID - T4E_HelloID_Users
*	Tools4ever - HelloID - T4E_HelloID_UserGroups

### Target

When the connector is defined as target system, only the following GetConnector is used by HelloID:

*	Tools4ever - HelloID - T4E_HelloID_Users

In addition to use to the above get-connector, the connector also uses the following build-in Profit update-connectors:

*	KnEmployee

<!-- USAGE EXAMPLES -->
## Setup the PowerShell connector

1. Add a new 'Target System' to HelloID and make sure to import all the necessary files.

    - [ ] configuration.json
    - [ ] create.ps1
    - [ ] update.ps1    
    - [ ] delete.ps1    

2. Fill in the required fields on the 'Configuration' tab.
 
![image](./assets/config.png)

_For more information about our HelloID PowerShell connectors, please refer to our general [Documentation](https://docs.helloid.com/hc/en-us/articles/360012558020-How-to-configure-a-custom-PowerShell-target-connector) page_

# HelloID Docs
The official HelloID documentation can be found at: https://docs.helloid.com/
