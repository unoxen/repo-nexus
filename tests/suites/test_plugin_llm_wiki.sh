#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# File: tests/suites/test_plugin_llm_wiki.sh
# Architectural Layer: Quality Assurance / Plugin Test Suite Runner
# Design Pattern: Test Suite Adapter (Indirection)
# Responsibilities:
#   - Exposes LLM Wiki verification suite within tests/suites/.
#   - Seamlessly delegates execution to plugins/llm-wiki/tests/test_plugin.sh.
#   - Enforces zero code duplication (DRY) between core suite runner and plugin tests.
# ============================================================================
set -e

[ -n "$DIR" ] && [ -f "$DIR/rnex" ] || DIR="$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)"
[ -f "$DIR/rnex" ] || DIR="$(cd "$(dirname "$0")/../../.." 2>/dev/null && pwd)"
# shellcheck source=tests/test_helper.sh
. "$DIR/tests/test_helper.sh"

# Execute LLM Wiki integration and contract test suite
# shellcheck source=plugins/llm-wiki/tests/test_plugin.sh
. "$DIR/plugins/llm-wiki/tests/test_plugin.sh"
