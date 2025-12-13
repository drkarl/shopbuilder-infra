output "database_id" {
  description = "Unique identifier of the Upstash Redis database"
  value       = upstash_redis_database.this.database_id
}

output "database_name" {
  description = "Name of the Redis database"
  value       = upstash_redis_database.this.database_name
}

output "endpoint" {
  description = "Redis endpoint hostname"
  value       = upstash_redis_database.this.endpoint
}

output "port" {
  description = "Redis port number"
  value       = upstash_redis_database.this.port
}

output "password" {
  description = "Redis authentication password"
  value       = upstash_redis_database.this.password
  sensitive   = true
}

output "rest_token" {
  description = "REST API token for Upstash Redis REST API"
  value       = upstash_redis_database.this.rest_token
  sensitive   = true
}

output "read_only_rest_token" {
  description = "Read-only REST API token"
  value       = upstash_redis_database.this.read_only_rest_token
  sensitive   = true
}

output "state" {
  description = "Current state of the database"
  value       = upstash_redis_database.this.state
}

output "creation_time" {
  description = "Timestamp when the database was created"
  value       = upstash_redis_database.this.creation_time
}

#------------------------------------------------------------------------------
# Connection String Outputs
# Format: rediss://default:[password]@[endpoint]:6379
# Note: Uses 'rediss://' (double 's') for TLS connections
#------------------------------------------------------------------------------

output "redis_url" {
  description = "Full Redis connection URL with TLS (rediss://). Use this for UPSTASH_REDIS_URL environment variable."
  value       = "rediss://default:${upstash_redis_database.this.password}@${upstash_redis_database.this.endpoint}:${upstash_redis_database.this.port}"
  sensitive   = true
}

output "redis_url_spring" {
  description = "Redis URL formatted for Spring Data Redis (spring.data.redis.url)"
  value       = "rediss://default:${upstash_redis_database.this.password}@${upstash_redis_database.this.endpoint}:${upstash_redis_database.this.port}"
  sensitive   = true
}

#------------------------------------------------------------------------------
# Summary Output
#------------------------------------------------------------------------------

output "connection_info" {
  description = "Connection information summary (non-sensitive)"
  value = {
    database_id   = upstash_redis_database.this.database_id
    database_name = upstash_redis_database.this.database_name
    endpoint      = upstash_redis_database.this.endpoint
    port          = upstash_redis_database.this.port
    tls_enabled   = var.tls_enabled
    region        = var.region
    environment   = var.environment
  }
}
