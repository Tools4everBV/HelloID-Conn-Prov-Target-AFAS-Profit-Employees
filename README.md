# HelloID-Conn-Prov-Target-AFAS-Profit-Employees
This connector contains the AFAS Profit target based on the GET connectors 'T4E_IAM3_Persons' and the UPDATE connector 'KnEmployee' for the HelloID provisioning module.
Since we won't create employees with a target connector the create action is just an update.
Also, because of this, we only have the create and update action, no enable, disable or delete ations.
