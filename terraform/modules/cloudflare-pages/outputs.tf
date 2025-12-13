output "project_id" {
  description = "ID of the Cloudflare Pages project"
  value       = cloudflare_pages_project.this.id
}

output "project_name" {
  description = "Name of the Cloudflare Pages project"
  value       = cloudflare_pages_project.this.name
}

output "subdomain" {
  description = "Default pages.dev subdomain for the project"
  value       = cloudflare_pages_project.this.subdomain
}

output "pages_url" {
  description = "Full pages.dev URL for the project"
  value       = "https://${cloudflare_pages_project.this.subdomain}.pages.dev"
}

#------------------------------------------------------------------------------
# Custom Domain Outputs
#------------------------------------------------------------------------------

output "custom_domain" {
  description = "Primary custom domain if configured"
  value       = var.custom_domain
}

output "custom_domain_id" {
  description = "ID of the primary custom domain resource"
  value       = length(cloudflare_pages_domain.primary) > 0 ? cloudflare_pages_domain.primary[0].id : null
}

output "www_redirect_domain" {
  description = "WWW redirect domain if configured"
  value       = var.www_redirect_domain
}

output "www_redirect_domain_id" {
  description = "ID of the WWW redirect domain resource"
  value       = length(cloudflare_pages_domain.www_redirect) > 0 ? cloudflare_pages_domain.www_redirect[0].id : null
}

#------------------------------------------------------------------------------
# Build Configuration Outputs
#------------------------------------------------------------------------------

output "build_config" {
  description = "Build configuration for the Pages project"
  value = {
    build_command   = var.build_command
    output_dir      = var.build_output_directory
    root_dir        = var.build_root_directory
    prod_branch     = var.production_branch
  }
}

#------------------------------------------------------------------------------
# Deployment Information
#------------------------------------------------------------------------------

output "deployment_info" {
  description = "Information needed for CI/CD deployments"
  value = {
    project_name = cloudflare_pages_project.this.name
    account_id   = var.account_id
    domains = compact([
      "https://${cloudflare_pages_project.this.subdomain}.pages.dev",
      var.custom_domain != null ? "https://${var.custom_domain}" : null,
      var.www_redirect_domain != null ? "https://${var.www_redirect_domain}" : null
    ])
  }
}
