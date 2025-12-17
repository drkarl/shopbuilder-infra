# Hetzner GitHub Runner Module - Variables

variable "name" {
  description = "Name of the runner VM"
  type        = string
  default     = "github-runner-1"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.name)) && length(var.name) >= 3 && length(var.name) <= 63
    error_message = "Name must be 3-63 characters, start with a letter, end with alphanumeric, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "server_type" {
  description = "Hetzner server type (cpx32, cpx42, ccx23, etc.)"
  type        = string
  default     = "cpx32"
}

variable "location" {
  description = "Hetzner datacenter location (nbg1, fsn1, hel1, ash, hil)"
  type        = string
  default     = "nbg1"

  validation {
    condition     = contains(["nbg1", "fsn1", "hel1", "ash", "hil", "sin"], var.location)
    error_message = "Location must be one of: nbg1, fsn1, hel1, ash, hil, sin."
  }
}

variable "image" {
  description = "OS image to use"
  type        = string
  default     = "ubuntu-24.04"
}

variable "ssh_public_key" {
  description = "SSH public key content"
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^ssh-(rsa|ed25519|ecdsa)", var.ssh_public_key))
    error_message = "SSH public key must be a valid SSH public key."
  }
}

variable "ssh_key_name" {
  description = "Name for the SSH key in Hetzner"
  type        = string
  default     = "github-runner-key"
}

#------------------------------------------------------------------------------
# Runner User Configuration
#------------------------------------------------------------------------------

variable "runner_user" {
  description = "Username for the GitHub Actions runner (non-root)"
  type        = string
  default     = "runner"

  validation {
    condition     = var.runner_user != "root" && can(regex("^[a-z_][a-z0-9_-]*$", var.runner_user))
    error_message = "Runner user must be a valid Unix username and cannot be 'root'."
  }
}

variable "runner_labels" {
  description = "Labels for the GitHub Actions runner (comma-separated)"
  type        = list(string)
  default     = ["self-hosted", "linux", "x64", "hetzner"]
}

#------------------------------------------------------------------------------
# Security Configuration
#------------------------------------------------------------------------------

variable "ssh_port" {
  description = "SSH port (change from 22 for reduced noise)"
  type        = number
  default     = 22

  validation {
    condition     = var.ssh_port > 0 && var.ssh_port <= 65535
    error_message = "SSH port must be between 1 and 65535."
  }
}

variable "ssh_allowed_ips" {
  description = "List of CIDR blocks allowed to SSH (empty = all)"
  type        = list(string)
  default     = []
}

variable "fail2ban_maxretry" {
  description = "Number of failures before IP is banned"
  type        = number
  default     = 3
}

variable "fail2ban_bantime" {
  description = "Ban duration in seconds"
  type        = number
  default     = 3600
}

#------------------------------------------------------------------------------
# Software Installation
#------------------------------------------------------------------------------

variable "install_docker" {
  description = "Install Docker on the runner"
  type        = bool
  default     = true
}

variable "install_java" {
  description = "Install Java/JDK on the runner"
  type        = bool
  default     = true
}

variable "java_version" {
  description = "Java version to install (17, 21, 25)"
  type        = number
  default     = 25
}

variable "install_gradle" {
  description = "Install Gradle on the runner"
  type        = bool
  default     = false # Usually Gradle wrapper is used
}

variable "install_nodejs" {
  description = "Install Node.js on the runner (for UI/frontend builds)"
  type        = bool
  default     = false
}

variable "nodejs_version" {
  description = "Node.js major version to install (20, 22)"
  type        = number
  default     = 22
}

variable "extra_packages" {
  description = "Additional apt packages to install"
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
# Cleanup Configuration
#------------------------------------------------------------------------------

variable "enable_cleanup_timer" {
  description = "Enable weekly cleanup of old CI artifacts"
  type        = bool
  default     = true
}

variable "cleanup_docker_after_hours" {
  description = "Clean Docker resources older than this many hours"
  type        = number
  default     = 168 # 7 days
}

variable "cleanup_workspace_after_days" {
  description = "Clean workspace directories older than this many days"
  type        = number
  default     = 7
}

#------------------------------------------------------------------------------
# GitHub Runner Auto-Registration (Optional)
#------------------------------------------------------------------------------

variable "auto_register_runner" {
  description = "Automatically register the runner with GitHub (requires github_token)"
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
  description = "GitHub owner (user or org) for runner registration"
  type        = string
  default     = ""
}

variable "github_repository" {
  description = "GitHub repository name for runner registration (without owner)"
  type        = string
  default     = ""
}

variable "runner_name" {
  description = "Name for the GitHub runner (defaults to server name)"
  type        = string
  default     = ""
}

variable "runner_count" {
  description = "Number of runner instances to install on this server (for parallel jobs)"
  type        = number
  default     = 1

  validation {
    condition     = var.runner_count >= 1 && var.runner_count <= 4
    error_message = "Runner count must be between 1 and 4."
  }
}

variable "runner_group" {
  description = "Runner group to add the runner to (org-level only)"
  type        = string
  default     = "Default"
}

#------------------------------------------------------------------------------
# Tags
#------------------------------------------------------------------------------

variable "labels" {
  description = "Labels to apply to the server"
  type        = map(string)
  default     = {}
}
