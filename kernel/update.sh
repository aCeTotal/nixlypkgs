#!/usr/bin/env bash
# Oppdaterer alle kernelkilder.
set -euo pipefail
cd "$(dirname "$0")"

latest=$(curl -sf 'https://api.github.com/repos/CachyOS/linux/releases?per_page=30' |
  grep -oE '"tag_name": "cachyos-[0-9]+\.[0-9]+\.[0-9]+-[0-9]+"' |
  grep -oE 'cachyos-[0-9]+\.[0-9]+\.[0-9]+-[0-9]+' | sort -Vu | tail -1)
current=$(grep -oE 'cachyos-[0-9]+\.[0-9]+\.[0-9]+-[0-9]+' ../flake.nix)
if [ "$latest" != "$current" ]; then
  echo "Oppdaterer $current -> $latest"
  sed -i "s|$current|$latest|" ../flake.nix
fi
# Enterprise følger kernel.org sin nyeste stabile.
releases=$(curl -sf https://www.kernel.org/releases.json)
newest=$(jq -r .latest_stable.version <<< "$releases")
sed -i -E "s|v[0-9]+\.x/linux-[0-9.]+\.tar\.xz|v${newest%%.*}.x/linux-$newest.tar.xz|" ../flake.nix
(cd .. && nix flake update linux-src linux-vanilla cachy-config cachy-patches)

base=${latest#cachyos-}
base=${base%-*}
series=${base%.*}
stable=$(jq -r --arg s "$series." '[.releases[].version | select(startswith($s))] | max_by(split(".") | map(tonumber))' <<< "$releases")
src=$(nix eval --raw --impure --expr "(builtins.getFlake \"path:$(cd .. && pwd)\").inputs.linux-src.outPath")
vanilla=https://raw.githubusercontent.com/gregkh/linux
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

entries=""
for ((sub = ${base##*.} + 1; sub <= ${stable##*.}; sub++)); do
  url="https://cdn.kernel.org/pub/linux/kernel/v${series%%.*}.x/incr/patch-$series.$((sub - 1))-$sub.xz"
  hash=$(nix hash convert --hash-algo sha256 --to sri "$(nix-prefetch-url --type sha256 "$url" 2>/dev/null)")
  curl -sf "$url" | xz -dc >> "$work/chain.patch"
  entries+=$(printf '\n    {\n      url = "%s";\n      hash = "%s";\n    }' "$url" "$hash")
done

# Ny fil kjeden lager i stedet for slettede $1.
renamed_to() {
  local best="" score=0 lines common g
  grep -qx -- "- $1" "$work/status" || return 0
  lines=$(wc -l < "$work/base")
  while read -r g; do
    added "$g" > "$work/candidate"
    common=$(comm -12 <(sort "$work/base") <(sort "$work/candidate") | wc -l)
    (( common * 2 > lines && common > score )) && best=$g score=$common
  done < <(sed -n 's/^+ //p' "$work/status")
  echo "$best"
}

# Innholdet kjeden gir ny fil $1.
added() {
  filterdiff -p1 -i "$1" "$work/chain.patch" | sed -n '/^@@/,${/^+/s/^+//p}'
}

# Filene CachyOS også har endret, slås sammen tre-veis.
conflicts=()
: > stable-fixup.patch
if [ -s "$work/chain.patch" ]; then
  mkdir "$work/tree"
  lsdiff -s --strip=1 "$work/chain.patch" > "$work/status"
  lsdiff --strip=1 "$work/chain.patch" | sort -u | while read -r f; do
    [ -e "$src/$f" ] && install -Dm644 "$src/$f" "$work/tree/$f"
  done
  (cd "$work/tree" && patch -p1 -N --batch --no-backup-if-mismatch < "$work/chain.patch" > "$work/patch.log" || :)
  mapfile -t conflicts < <(cd "$work/tree" && find . -name '*.rej' | sed 's|^\./||; s|\.rej$||' | sort)
  for f in "${conflicts[@]}"; do
    curl -sf --retry 5 --retry-delay 2 "$vanilla/v$base/$f" -o "$work/base"
    target=$(renamed_to "$f")
    if [ -n "$target" ]; then
      added "$target" > "$work/stable"
    else
      cp "$work/base" "$work/stable"
      filterdiff -p1 -i "$f" "$work/chain.patch" | patch -s -p1 "$work/stable"
    fi
    rc=0
    git merge-file -p --theirs "$src/$f" "$work/base" "$work/stable" > "$work/merged" || rc=$?
    if (( rc > 127 )) || [ ! -s "$work/merged" ]; then
      echo "Klarte ikke å slå sammen $f" >&2
      exit 1
    fi
    if [ -n "$target" ]; then
      diff -u --label "a/$f" --label /dev/null "$src/$f" /dev/null >> stable-fixup.patch || :
      diff -u --label "a/$target" --label "b/$target" "$work/stable" "$work/merged" >> stable-fixup.patch || :
    else
      diff -u --label "a/$f" --label "b/$f" "$src/$f" "$work/merged" >> stable-fixup.patch || :
    fi
  done
fi

{
  echo "# Stabilpatcher oppå CachyOS-taggen."
  echo "{"
  echo "  patches = [$entries"
  echo "  ];"
  echo "  # Slås sammen i stable-fixup.patch."
  printf '  conflicts = [%s ];\n' "$(printf ' "%s"' "${conflicts[@]}")"
  echo "}"
} > stable.nix
echo "Kernel $stable ($latest + ${#conflicts[@]} sammenslåtte filer), enterprise $newest"
