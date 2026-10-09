#!/usr/bin/env bash
# Updates spec/openapi.yaml, the copy of the public OpenAPI description of
# Limenia (the /v1 operations for app backends and the webhook events) that
# test/spec_test.dart checks the package against. Run it after every change of
# the Limenia API and fix what the test then reports.
#
#   tool/sync_openapi.sh [URL or local file, default https://limenia.eu/openapi/v1.yaml]
set -euo pipefail
cd "$(dirname "$0")/.."
src="${1:-https://limenia.eu/openapi/v1.yaml}"
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
case "$src" in
  http://* | https://*) curl -fsSL --proto '=https' "$src" -o "$tmp" ;;
  *) test -f "$src" || { echo "Not found: $src" >&2; exit 1; }; cp "$src" "$tmp" ;;
esac
grep -q '^openapi: ' "$tmp" || { echo "Not an OpenAPI document: $src" >&2; exit 1; }
mv "$tmp" spec/openapi.yaml
trap - EXIT
echo "spec/openapi.yaml updated from $src (API version $(sed -n 's/^  version: *//p' spec/openapi.yaml | head -1))"
