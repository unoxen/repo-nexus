#!/bin/sh
# shellcheck shell=sh
# Delegation wrapper for karpathy-llm graph
exec "$(dirname "$0")/../commands/graph.sh" "$@"
