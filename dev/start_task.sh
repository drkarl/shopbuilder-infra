#!/usr/bin/env bash
# Thin wrapper - calls central start_task.sh with repo context
# Copy this to <repo>/dev/start_task.sh

exec ~/.scripts/start_task.sh "$@"
