Clone this repo and run the following commands to deploy the solution via ARM and az cli.

```
az login

az account set –subscription <subscription id>

az group create -l west europe -n compliancecenter-rg

az deployment group create --resource-group compliancecenter-rg --template-file compliance-center-resources.json --parameters compliance-center-resources.parameters.json --name deploymentname1

az functionapp deployment source config-zip --resource-group compliancecenter-rg --name compliancecenterprmfunction2 --src compliancecenter2.zip

az deployment group create --resource-group compliancecenter_rg --template-file compliance-center-event-grid.json --parameters compliance-center-event-grid.parameters.json --name edeploy1

```
