#!/bin/bash

#########################################################

packer_template_path=<full path to Packer template>

terraform_project_location=<full path to Terraform project>

##########################################################

# Pleaee define location of Packer template and
# Terraform project above

# This script will assume your Terraform template is
# using "ami" for the AMI variable name. Please make sure you
# have initialized and referenced it in the appropriate .tf
# files and Terraform resource. Once the AMI is created
# this script will explicitly assign the AMI ID to "ami"
# in the terraform.tfvars file.

##########################################################

# Checking to see if the Packer template and Terraform directory
# actually exist in the specified paths

if [ ! -f $packer_template_path ]; then
        printf "\n$packer_template_path does not exist\n\n"
        exit 1
fi

if [ ! -d $terraform_project_location ]; then
        printf "\nterraform_project_location does not exist\n\n"
        exit 1
fi

# Since Packer failed validation does not register as stderr,
# this script will redirect stdout to packer_error.log and then
# delete the log if validation is successful

packer_parent=$(dirname $packer_template_path)
packer_template=$(basename $packer_template_path)

# This script will use the cd command to change into certain directories
# so that there are no errors if the Packer or Terraform templates are 
# referencing any relative files or directories

cd $packer_parent

packer validate $packer_template > $packer_parent/packer_error.log

if [ $? -ne 0 ]; then
        printf "\nPacker validation failed. Please check\n"
        printf "packer_error.log (located in $packer_parent)\n"
	printf "to fix issues and retry script.\n\n"
        exit 1
else
        rm -rf $packer_parent/packer_error.log
        printf "\nPacker validation succeeded\n"
        sleep 1
fi

cd $terraform_project_location 
terraform validate > /dev/null 2> tf_validation.log

if [ $? -ne 0 ]; then
        printf "\nTerraform validation failed. Please check\n"
        printf "tf_validation.log (located in $$terraform_project_location)\n" 
	printf "to fix issues and retry script.\n\n"
        exit 1
else
	rm -rf tf_validation.log
        printf "\nTerraform validation succeeded\n"
        sleep 1
fi

printf "\nProceeding to build AMI and pass it to Terraform for deployment\n\n"
printf "\nThis will take a few moments...\n\n"
sleep 1

cd $packer_parent

ami=$(packer build -machine-readable $packer_template | tee /dev/tty | awk -F: '/artifact,0,id/ {print $2}')

echo "ami = \""$ami"\"" >> $terraform_project_location/terraform.tfvars

printf "\nProceeding to deploy $ami with Terraform\n\n"
sleep 1

cd $terraform_project_location

terraform apply 2> tf_deployment_error.log

if [ $? -eq 0 ]; then
	rm -rf tf_deployment_error.log
	printf "\nDeploy complete\n\n"
else
	printf "\nThere was an error\n"
	printf "Please check tf_deployment_error.log\n"
	printf "(located in $terraform_project_location)\n\n"
	exit 1
fi

# The following checks to see if the ami variable is present in the last
# line of terraform.tfvars. If it is present, this script will delete it
# so the user can re-run this script if need be without causing errors

# Please note if you need to run "terraform destroy" later, Terraform
# will ask you to input the ami variable value. You can grep for this
# in the terraform.tfstate file if the ami variable value is gone

tail -1 terraform.tfvars | grep -iq "ami = \""$ami"\"" 

if [ $? -eq 0 ]; then
	sed -i '$ d' terraform.tfvars
fi

