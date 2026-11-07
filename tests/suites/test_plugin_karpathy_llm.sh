#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# File: tests/suites/test_plugin_karpathy_llm.sh
# Architectural Layer: Quality Assurance / Plugin Test Suite Runner
# Design Pattern: Test Suite Adapter (Indirection)
# Responsibilities:
#   - Exposes Karpathy LLM Wiki verification suite within tests/suites/.
#   - Seamlessly delegates execution to plugins/karpathy-llm/tests/test_plugin.sh.
#   - Enforces zero code duplication (DRY) between core suite runner and plugin tests.
# ============================================================================
set -e

[ -n "$DIR" ] && [ -f "$DIR/rnex" ] || DIR="$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)"
[ -f "$DIR/rnex" ] || DIR="$(cd "$(dirname "$0")/../../.." 2>/dev/null && pwd)"
# shellcheck source=tests/test_helper.sh
. "$DIR/tests/test_helper.sh"

# Execute Karpathy LLM Wiki integration and contract test suite
# shellcheck source=plugins/karpathy-llm/tests/test_plugin.sh
. "$DIR/plugins/karpathy-llm/tests/test_plugin.sh"
