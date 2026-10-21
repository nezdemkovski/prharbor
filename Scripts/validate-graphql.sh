#!/bin/bash
# Exports every GraphQL document the client sends and validates it against GitHub's schema.
# Scripts/graphql/selected-fields.txt records the selected fields and their nullability;
# review its diff whenever a query changes. Requires Node.js.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
documents="$(mktemp -d "${TMPDIR:-/tmp}/prharbor-graphql.XXXXXX")"
trap 'rm -rf "$documents"' EXIT

npm ci --prefix "$root/Scripts/graphql" --silent
# Unsigned, so the test host runs outside the sandbox and can write the documents.
TEST_RUNNER_PRHARBOR_GRAPHQL_EXPORT="$documents" xcodebuild test \
    -project "$root/PRHarbor.xcodeproj" -scheme PRHarbor -destination 'platform=macOS' \
    -only-testing:PRHarborTests/GraphQLDocumentTests CODE_SIGNING_ALLOWED=NO -quiet
node "$root/Scripts/graphql/validate.mjs" "$documents" "$root/Scripts/graphql/selected-fields.txt"
