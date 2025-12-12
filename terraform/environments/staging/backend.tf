# Backend Configuration for Staging Environment
# Using local backend initially, can be migrated to remote backend later

terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}

# To migrate to a remote backend (e.g., S3, Scaleway Object Storage):
# 1. Uncomment the appropriate backend configuration below
# 2. Run: terraform init -migrate-state
#
# Scaleway Object Storage Backend:
# terraform {
#   backend "s3" {
#     bucket                      = "shopbuilder-terraform-state"
#     key                         = "staging/terraform.tfstate"
#     region                      = "fr-par"
#     endpoint                    = "https://s3.fr-par.scw.cloud"
#     skip_credentials_validation = true
#     skip_region_validation      = true
#     skip_metadata_api_check     = true
#   }
# }
