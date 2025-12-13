# Cloudflare Pages Module
# This module manages Cloudflare Pages projects for static site hosting

terraform {
  required_version = ">= 1.0"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
}

#------------------------------------------------------------------------------
# Cloudflare Pages Project
#------------------------------------------------------------------------------

resource "cloudflare_pages_project" "this" {
  account_id        = var.account_id
  name              = var.project_name
  production_branch = var.production_branch

  build_config {
    build_command   = var.build_command
    destination_dir = var.build_output_directory
    root_dir        = var.build_root_directory
  }

  dynamic "deployment_configs" {
    for_each = var.enable_deployment_configs ? [1] : []
    content {
      preview {
        environment_variables = var.preview_environment_variables
      }
      production {
        environment_variables = var.production_environment_variables
      }
    }
  }
}

#------------------------------------------------------------------------------
# Custom Domain Configuration
# Adds custom domain to the Pages project
#------------------------------------------------------------------------------

resource "cloudflare_pages_domain" "primary" {
  count = var.custom_domain != null ? 1 : 0

  account_id   = var.account_id
  project_name = cloudflare_pages_project.this.name
  domain       = var.custom_domain
}

resource "cloudflare_pages_domain" "www_redirect" {
  count = var.www_redirect_domain != null ? 1 : 0

  account_id   = var.account_id
  project_name = cloudflare_pages_project.this.name
  domain       = var.www_redirect_domain
}
