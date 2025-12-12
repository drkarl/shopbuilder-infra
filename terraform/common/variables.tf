# Common Variables Reference
# ==========================
# This file serves as DOCUMENTATION ONLY - it is not used by Terraform.
# Each environment (dev, staging, prod) should define these variables
# in environments/<env>/variables.tf to maintain consistency.

# variable "environment" {
#   description = "Environment name (dev, staging, prod)"
#   type        = string
#
#   validation {
#     condition     = contains(["dev", "staging", "prod"], var.environment)
#     error_message = "Environment must be one of: dev, staging, prod."
#   }
# }

# variable "project_name" {
#   description = "Name of the project"
#   type        = string
#   default     = "shopbuilder"
# }

# OVH Provider Variables
# variable "ovh_endpoint" {
#   description = "OVH API endpoint (ovh-eu, ovh-ca, ovh-us, etc.)"
#   type        = string
#   default     = "ovh-eu"
# }

# Scaleway Provider Variables
# variable "scaleway_region" {
#   description = "Scaleway region"
#   type        = string
#   default     = "fr-par"
# }
#
# variable "scaleway_zone" {
#   description = "Scaleway availability zone"
#   type        = string
#   default     = "fr-par-1"
# }

# Common Tags
# variable "common_tags" {
#   description = "Common tags to apply to all resources"
#   type        = map(string)
#   default     = {}
# }
