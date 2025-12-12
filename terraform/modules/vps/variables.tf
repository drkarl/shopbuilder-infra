variable "name" {
  description = "Name of the VPS instance"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "instance_type" {
  description = "Instance type/size for the VPS"
  type        = string
}

variable "region" {
  description = "Region where the VPS will be deployed"
  type        = string
}

variable "tags" {
  description = "Tags to apply to the VPS instance"
  type        = map(string)
  default     = {}
}
