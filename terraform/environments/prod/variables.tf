# Production Environment Variables

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "shopbuilder"
}

# OVH Provider Variables
variable "ovh_endpoint" {
  description = "OVH API endpoint (ovh-eu, ovh-ca, ovh-us, etc.)"
  type        = string
  default     = "ovh-eu"
}

# Scaleway Provider Variables
variable "scaleway_region" {
  description = "Scaleway region"
  type        = string
  default     = "fr-par"
}

variable "scaleway_zone" {
  description = "Scaleway availability zone"
  type        = string
  default     = "fr-par-1"
}

# Common Tags
variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# VPS Configuration
variable "vps_instance_type" {
  description = "Instance type for VPS (Scaleway instance type)"
  type        = string
  default     = "GP1-S"
}
