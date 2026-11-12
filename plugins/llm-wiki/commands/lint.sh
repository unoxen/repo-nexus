#!/bin/sh
# shellcheck shell=sh
# Delegation wrapper for llm-wiki lint
exec "$(dirname "$0")/../bin/lint.sh" "$@"
