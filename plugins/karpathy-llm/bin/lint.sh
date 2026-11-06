#!/bin/sh
# shellcheck shell=sh
# Delegation wrapper for karpathy-llm lint
exec "$(dirname "$0")/../commands/lint.sh" "$@"
