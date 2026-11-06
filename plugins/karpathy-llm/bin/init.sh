#!/bin/sh
# shellcheck shell=sh
# Delegation wrapper for karpathy-llm init
exec "$(dirname "$0")/../commands/init.sh" "$@"
