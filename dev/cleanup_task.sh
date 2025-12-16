#!/usr/bin/env bash
# Thin wrapper - calls central cleanup_task.sh with repo context
# Copy this to <repo>/dev/cleanup_task.sh

exec ~/.scripts/cleanup_task.sh "$@"
