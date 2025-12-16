# CI Environment Variables

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "shopbuilder"
}

#------------------------------------------------------------------------------
# Server Configuration
#------------------------------------------------------------------------------

variable "runner_name" {
  description = "Name of the runner VM"
  type        = string
  default     = "github-runner-1"
}

variable "server_type" {
  description = "Hetzner server type"
  type        = string
  default     = "cpx32"  # 4 vCPU, 8GB RAM, 160GB NVMe
}

variable "location" {
  description = "Hetzner datacenter location"
  type        = string
  default     = "nbg1"  # Nuremberg, Germany
}

variable "image" {
  description = "OS image"
  type        = string
  default     = "ubuntu-24.04"
}

#------------------------------------------------------------------------------
# SSH Configuration
#------------------------------------------------------------------------------

variable "ssh_public_key" {
  description = "SSH public key for server access"
  type        = string
  sensitive   = true
}

variable "ssh_key_name" {
  description = "Name for SSH key in Hetzner"
  type        = string
  default     = "github-runner-key"
}

variable "ssh_port" {
  description = "SSH port"
  type        = number
  default     = 22
}

variable "ssh_allowed_ips" {
  description = "IPs allowed to SSH (empty = all)"
  type        = list(string)
  default     = []
}

#------------------------------------------------------------------------------
# Runner Configuration
#------------------------------------------------------------------------------

variable "runner_user" {
  description = "Non-root user for the runner"
  type        = string
  default     = "runner"
}

variable "runner_labels" {
  description = "GitHub Actions runner labels"
  type        = list(string)
  default     = ["self-hosted", "linux", "x64", "hetzner", "builder"]
}

#------------------------------------------------------------------------------
# Security
#------------------------------------------------------------------------------

variable "fail2ban_maxretry" {
  description = "Failed attempts before ban"
  type        = number
  default     = 3
}

variable "fail2ban_bantime" {
  description = "Ban duration in seconds"
  type        = number
  default     = 3600
}

#------------------------------------------------------------------------------
# Software
#------------------------------------------------------------------------------

variable "install_docker" {
  description = "Install Docker"
  type        = bool
  default     = true
}

variable "install_java" {
  description = "Install Java"
  type        = bool
  default     = true
}

variable "java_version" {
  description = "Java version (17, 21, 25)"
  type        = number
  default     = 25
}

variable "extra_packages" {
  description = "Additional packages to install"
  type        = list(string)
  default = [
    "htop",
    "ncdu",
    "tmux",
    "jq",
    "unzip",
    "ripgrep",
    "fd-find",
    "bat",
    "duf"
  ]
}

#------------------------------------------------------------------------------
# Cleanup
#------------------------------------------------------------------------------

variable "enable_cleanup_timer" {
  description = "Enable weekly cleanup"
  type        = bool
  default     = true
}

variable "cleanup_docker_after_hours" {
  description = "Clean Docker resources older than hours"
  type        = number
  default     = 168
}

variable "cleanup_workspace_after_days" {
  description = "Clean workspace dirs older than days"
  type        = number
  default     = 7
}

#------------------------------------------------------------------------------
# GitHub Auto-Registration (Optional)
#------------------------------------------------------------------------------

variable "auto_register_runner" {
  description = "Automatically register runner with GitHub (requires github_token)"
  type        = bool
  default     = false
}

variable "github_token" {
  description = "GitHub PAT with repo scope (required if auto_register_runner = true)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "github_owner" {
  description = "GitHub owner (user or org)"
  type        = string
  default     = ""
}

variable "github_repository" {
  description = "GitHub repository name (without owner)"
  type        = string
  default     = ""
}
