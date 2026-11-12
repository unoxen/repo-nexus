#!/bin/sh
# shellcheck shell=sh
# Delegation wrapper for llm-wiki ingest
exec "$(dirname "$0")/../bin/ingest.sh" "$@"
