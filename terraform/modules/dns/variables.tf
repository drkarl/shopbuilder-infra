variable "zone_name" {
  description = "DNS zone name (domain)"
  type        = string
}

variable "records" {
  description = "List of DNS records to create"
  type = list(object({
    name  = string
    type  = string
    ttl   = number
    value = string
  }))
  default = []
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}
