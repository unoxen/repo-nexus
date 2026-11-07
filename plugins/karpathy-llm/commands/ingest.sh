#!/bin/sh
# shellcheck shell=sh
# Delegation wrapper for karpathy-llm ingest
exec "$(dirname "$0")/../bin/ingest.sh" "$@"
