# Releases come from the cache, never source.
CACHE_OPTS=(
  --option substituters 'https://cache.aceclan.no?priority=5 https://cache.nixos.org'
  --option extra-trusted-public-keys cache.aceclan.no-1:qfGAXabgsofKSAqId9sqqbPlQic4l7gOGeWPrqUg3ak=
  --option connect-timeout 3
  --option fallback false
)

# Source builds $1 would need.
uncached() {
  local -a drvs inputs
  local built
  mapfile -t drvs < <(nix-store --realise --dry-run "${CACHE_OPTS[@]}" "$1" 2>&1 |
    awk '/will be built:$/ { b = 1; next } /will be fetched/ { b = 0 } b && $1 ~ /\.drv$/ { print $1 }')
  (( ${#drvs[@]} )) || return 0
  built=$(nix derivation show "${drvs[@]}" | jq -c '
    def flag(k): (.env[k] // .structuredAttrs[k]) | tostring;
    [.derivations[]
     | select(flag("preferLocalBuild") | IN("1", "true") | not)
     | select(flag("allowSubstitutes") | IN("", "false") | not)
     | { name, inputs: (.inputs.drvs | keys) }]')
  mapfile -t inputs < <(jq -r '.[].inputs[] | "/nix/store/" + .' <<<"$built" | sort -u)
  (( ${#inputs[@]} )) || return 0
  # Machine glue may build locally.
  { printf '%s\n' "$built"; nix derivation show "${inputs[@]}"; } | jq -rn '
    input as $built
    | input.derivations | with_entries(select(.value.outputs | any(.hash))) as $fetched
    | $built[] | select(any(.inputs[]; $fetched[.])) | .name' | sort -u
}
