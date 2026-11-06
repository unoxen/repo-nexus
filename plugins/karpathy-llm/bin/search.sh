#!/bin/sh
# shellcheck shell=sh
# Delegation wrapper for karpathy-llm search
exec "$(dirname "$0")/../commands/search.sh" "$@"
