# CI Environment - Terraform Backend
# Using local backend for now. For production, consider remote state.

terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}

# Alternative: S3-compatible backend (e.g., Scaleway Object Storage)
# terraform {
#   backend "s3" {
#     bucket                      = "shopbuilder-terraform-state"
#     key                         = "ci/terraform.tfstate"
#     region                      = "fr-par"
#     endpoint                    = "https://s3.fr-par.scw.cloud"
#     skip_credentials_validation = true
#     skip_metadata_api_check     = true
#     skip_region_validation      = true
#   }
# }
