# Common Provider Configuration Reference
# ========================================
# This file serves as DOCUMENTATION ONLY - it is not used by Terraform.
# Each environment (dev, staging, prod) has its own provider configuration
# in environments/<env>/main.tf that should be kept in sync with this reference.
#
# Terraform does not support sharing provider configurations across modules
# in the way that other languages support shared libraries. Each root module
# (environment) must define its own providers.

# terraform {
#   required_version = ">= 1.0"
#
#   required_providers {
#     ovh = {
#       source  = "ovh/ovh"
#       version = "~> 0.40"
#     }
#
#     scaleway = {
#       source  = "scaleway/scaleway"
#       version = "~> 2.0"
#     }
#   }
# }

# OVH Provider
# Credentials should be set via environment variables:
# - OVH_ENDPOINT
# - OVH_APPLICATION_KEY
# - OVH_APPLICATION_SECRET
# - OVH_CONSUMER_KEY
#
# provider "ovh" {
#   endpoint = var.ovh_endpoint
# }

# Scaleway Provider
# Credentials should be set via environment variables:
# - SCW_ACCESS_KEY
# - SCW_SECRET_KEY
# - SCW_DEFAULT_PROJECT_ID
#
# provider "scaleway" {
#   region = var.scaleway_region
#   zone   = var.scaleway_zone
# }
