#!/bin/sh
# shellcheck shell=sh
# Delegation wrapper for karpathy-llm index
exec "$(dirname "$0")/../commands/index.sh" "$@"
