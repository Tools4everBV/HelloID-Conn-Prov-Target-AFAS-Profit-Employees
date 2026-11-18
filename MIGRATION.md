# Migration

## From version 4.x to 5.0.0

> [!WARNING]
> Version 5.0.0 is **not backward compatible** with version 4.x. Do not replace the scripts of an existing 4.x target system that already has granted accounts.

### What has changed

| Item                      | Version 4.x                                        | Version 5.0.0                                                                     |
| ------------------------- | -------------------------------------------------- | --------------------------------------------------------------------------------- |
| Account reference         | Object with `Medewerker` and `Persoonsnummer`      | Employee number `EmId` (string)                                                   |
| Account correlation field | `Medewerker`                                       | `EmId`                                                                            |
| GetConnector              | `T4E_HelloID_Users_v2`                             | `T4E_HelloID_Target_Employees`, with field ids equal to the AFAS field codes      |
| Field mapping             | `Medewerker`, `Persoonsnummer`, `EmAd`             | `EmId`, `BcCo`, `EmAd`                                                            |
| Free fields               | Script changes                                     | GetConnector and field mapping only, see [Free fields](./README.md#free-fields)   |
| Configuration             | `onlyUpdateOnCorrelate`, `isDebug`                 | Removed; added `DeleteMode`                                                       |

The scripts look up the employee by `EmId` and expect the account reference as a string. An account reference of version 4.x is rejected, so every action on an existing 4.x account fails.

### Migration steps

Because this is a correlate-only connector, the upgrade is a **clean go-live** of the connector:

1. Import the GetConnector [Tools4ever - HelloID - T4E_HelloID_Target_Employees.gcn](./Tools4ever%20-%20HelloID%20-%20T4E_HelloID_Target_Employees.gcn) in AFAS Profit and give the App Connector access to it. Add the fields of the current implementation, see [Adding fields](./README.md#adding-fields).
2. Configure the target system with the scripts, configuration, correlation and field mapping of this version.
3. Configure the account entitlement in the business rules.
4. Disable the old target system.
5. Use the entitlement import to import all existing account entitlements.
