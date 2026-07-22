#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
package_root="${script_dir:h:h}"
runner="$package_root/validation/ts-runner"
instant_cli="$runner/node_modules/.bin/instant-cli"
credential_dir="${INSTANT_RECIPES_CREDENTIAL_DIR:-${package_root:h}/private/credentials/swift-instant-data}"
credential_file="$credential_dir/recipes-v3.env"
response_file="$credential_dir/recipes-v3-getadb-response.txt"
local_config="$script_dir/RecipesV3.local.xcconfig"
fresh=0

if [[ "${1:-}" == "--fresh" ]]; then
  fresh=1
elif [[ $# -gt 0 ]]; then
  print -u2 "Usage: ${0:t} [--fresh]"
  exit 64
fi

if [[ ! -x "$instant_cli" ]]; then
  print -u2 "Missing pinned Instant CLI at $instant_cli"
  exit 1
fi

mkdir -p "$credential_dir"
chmod 700 "$credential_dir"

if [[ $fresh == 1 || ! -s "$credential_file" ]]; then
  provision_id="$(uuidgen | tr '[:upper:]' '[:lower:]')"
  curl -fsSL "https://www.getadb.com/provision/$provision_id" -o "$response_file"
  chmod 600 "$response_file"

  app_id="$(sed -n 's/^VITE_INSTANT_APP_ID=//p' "$response_file" | head -1)"
  admin_token="$(sed -n 's/^INSTANT_ADMIN_TOKEN=//p' "$response_file" | head -1)"
  if [[ ! "$app_id" =~ '^[0-9a-fA-F-]{36}$' || ! "$admin_token" =~ '^[A-Za-z0-9._-]+$' ]]; then
    print -u2 "getadb returned malformed credentials"
    exit 1
  fi

  umask 077
  printf 'VITE_INSTANT_APP_ID=%s\nNEXT_PUBLIC_INSTANT_APP_ID=%s\nINSTANT_APP_ID=%s\nINSTANT_ADMIN_TOKEN=%s\n' \
    "$app_id" "$app_id" "$app_id" "$admin_token" >"$credential_file"
  chmod 600 "$credential_file"
fi

app_id="$(sed -n 's/^INSTANT_APP_ID=//p' "$credential_file" | head -1)"
admin_token="$(sed -n 's/^INSTANT_ADMIN_TOKEN=//p' "$credential_file" | head -1)"
if [[ ! "$app_id" =~ '^[0-9a-fA-F-]{36}$' || ! "$admin_token" =~ '^[A-Za-z0-9._-]+$' ]]; then
  print -u2 "Stored recipes credentials are malformed"
  exit 1
fi

work_dir="$(mktemp -d /tmp/instant-recipes-v3-provision.XXXXXX)"
cleanup() {
  rm -rf "$work_dir"
}
trap cleanup EXIT INT TERM

cp "$runner/package.json" "$work_dir/package.json"
ln -s "$runner/node_modules" "$work_dir/node_modules"

swift run --package-path "$package_root" instant-swift-data schema generate \
  --example recipes --to "$work_dir/instant.schema.ts" --json >/dev/null
swift run --package-path "$package_root" instant-swift-data perms generate \
  --example recipes --to "$work_dir/instant.perms.ts" --json >/dev/null

export INSTANT_APP_ID="$app_id"
export INSTANT_ADMIN_TOKEN="$admin_token"
export INSTANT_APP_ADMIN_TOKEN="$admin_token"
export INSTANT_CLI_AUTH_TOKEN="$admin_token"
export CI=1
export NO_COLOR=1

(
  cd "$work_dir"
  "$instant_cli" push schema --yes
  "$instant_cli" push perms --yes
)

umask 077
printf 'INSTANT_APP_ID = %s\n' "$app_id" >"$local_config"
chmod 600 "$local_config"

print "Provisioned the aggregate recipes schema and wrote persistent local credentials."
print "Credentials: $credential_file"
print "Xcode config: $local_config"
