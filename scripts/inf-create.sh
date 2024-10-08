# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.

#!/bin/bash
set -e

figlet Infrastructure

# Get the directory that this script is in
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source "${DIR}/load-env.sh"
source "${DIR}/prepare-tf-variables.sh"
pushd "$DIR/../infra" > /dev/null

# reset the current directory on exit using a trap so that the directory is reset even on error
function finish {
  popd > /dev/null
}
trap finish EXIT

if [ -n "${IN_AUTOMATION}" ]; then
  export TF_VAR_isInAutomation=true
  
  if [[ $WORKSPACE = tmp* ]]; then
    # if in automation for PR builds, get the app registration and service principal values from the already logged in SP
    aadWebAppId=$ARM_CLIENT_ID
    aadMgmtAppId=$ARM_CLIENT_ID
    aadWebSPId=$ARM_SERVICE_PRINCIPAL_ID
    aadMgmtAppSecret=$ARM_CLIENT_SECRET
    aadMgmtSPId=$ARM_SERVICE_PRINCIPAL_ID
  else
    # if in automation for non-PR builds, get the app registration and service principal values from the manually created AD objects
    aadWebAppId=$AD_WEBAPP_CLIENT_ID
    if [ -z $aadWebAppId ]; then
      echo "An Azure AD App Registration and Service Principal must be manually created for the targeted workspace."
      echo "Please create the Azure AD objects using the script at /scripts/create-ad-objs-for-deployment.sh and set the AD_WEBAPP_CLIENT_ID pipeline variable in Azure DevOps."
      exit 1  
    fi
    aadMgmtAppId=$AD_MGMTAPP_CLIENT_ID
    aadMgmtAppSecret=$AD_MGMTAPP_CLIENT_SECRET
    aadMgmtSPId=$AD_MGMT_SERVICE_PRINCIPAL_ID

  fi

  # prepare the AD object variables for Terraform
  export TF_VAR_aadWebClientId=$aadWebAppId
  export TF_VAR_aadMgmtClientId=$aadMgmtAppId
  export TF_VAR_aadMgmtServicePrincipalId=$aadMgmtSPId
  export TF_VAR_aadMgmtClientSecret=$aadMgmtAppSecret
fi

if [ -n "${IN_AUTOMATION}" ]
then

    if [ -n "${AZURE_ENVIRONMENT}" ] && [[ $AZURE_ENVIRONMENT == "AzureUSGovernment" ]]; then
        az cloud set --name AzureUSGovernment 
    fi

    az login --service-principal -u "$ARM_CLIENT_ID" -p "$ARM_CLIENT_SECRET" --tenant "$ARM_TENANT_ID"
    az account set -s "$ARM_SUBSCRIPTION_ID"
fi

#If you are unable to obtain the permission at the tenant level described in Azure account requirements, you can set the following to true provided you have created Azure AD App Registrations. 

export TF_VAR_isInAutomation=true
# Access ID of web from GovTech
export TF_VAR_aadWebClientId="776f11b2-e282-438f-b4ff-8e758fb99cea"
# Access ID of TechPass from GovTech
export TF_VAR_aadMgmtClientId="934faaf3-e9d4-4d87-94ea-c0bc20eea8cc"
# Object ID of Techpass from GovTech
export TF_VAR_aadMgmtServicePrincipalId="14a2e156-468e-4f95-9bf6-c902383aa2e2"
# Key of Techpass from CMPs
export TF_VAR_aadMgmtClientSecret="ILK8Q~fdC7shxiCw_LHs~5cHPqBSm1Bht9kH4btV"


# prepare vars for the users you wish to assign to the security group
object_ids=()
# Remove spaces from the comma-separated string
ENTRA_OWNERS=$(echo "$ENTRA_OWNERS" | tr -d ' ')
IFS=',' read -ra ADDR <<< "$ENTRA_OWNERS"
for user_principal_name in "${ADDR[@]}"; do
  object_id=$(az ad user list --filter "mail eq '$user_principal_name'" --query "[0].id" -o tsv)
  # Check if the object_id is not empty before adding it to the array
  if [[ -n $object_id ]]; then
    object_ids+=($object_id)
    echo "user_principal_name: $user_principal_name and object_id: $object_id to be added as an owner"
  else
    echo "No object_id found for user_principal_name: $user_principal_name"
  fi
done
# Join the array of object IDs into a comma-separated string
object_ids_string=$(IFS=','; echo "${object_ids[*]}")
export TF_VAR_entraOwners=$object_ids_string


# Create our application configuration file before starting infrastructure
${DIR}/configuration-create.sh

# Initialise Terraform with the correct path
${DIR}/terraform-init.sh "$DIR/../infra/"

${DIR}/terraform-plan-apply.sh -d "$DIR/../infra" -p "infoasst" -o "$DIR/../inf_output.json"
