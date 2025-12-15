#!/usr/bin/env bash
# .task-config.sh - shopbuilder-infra (Infrastructure) configuration

ROLE_LABEL="Infrastructure"
TECH_STACK="Terraform / Docker / Kubernetes"
BUILD_TOOL="Terraform"
TEST_COMMAND="cd terraform && terraform validate && terraform fmt -check"
BUILD_COMMAND="cd terraform && terraform plan"

BUILD_COMMANDS="  - Format: \`terraform fmt\`
  - Validate: \`terraform validate\`
  - Plan: \`terraform plan\`
  - Apply: \`terraform apply\` (requires approval)
  - Docker build: \`docker build -t <image> docker/<service>/\`
  - Docker compose: \`docker-compose -f docker/docker-compose.yml up -d\`"
