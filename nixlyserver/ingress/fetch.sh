# Builds sets.nft; failures keep old.
set -euo pipefail

readonly min_vpn=1000
readonly min_datacenter=10000
readonly min_tor=100

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

get() {
  curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
    --max-time 300 --retry 3 -o "$work/$1" "$2"
}

# Header count proves completeness.
complete_rir() {
  awk -F'|' '
    /^#/ { next }
    !seen++ { want = $4; next }
    $6 != "summary" { n++ }
    END { exit !(want > 0 && n == want) }' "$work/$1"
}

at_least() {
  [ "$(wc -l < "$work/$1")" -ge "$2" ]
}

rirs=(ripe arin apnic lacnic afrinic)
get ripe https://ftp.ripe.net/pub/stats/ripencc/delegated-ripencc-extended-latest
get arin https://ftp.arin.net/pub/stats/arin/delegated-arin-extended-latest
get apnic https://ftp.apnic.net/stats/apnic/delegated-apnic-extended-latest
get lacnic https://ftp.lacnic.net/pub/stats/lacnic/delegated-lacnic-extended-latest
get afrinic https://ftp.afrinic.net/pub/stats/afrinic/delegated-afrinic-extended-latest
get vpn https://raw.githubusercontent.com/X4BNet/lists_vpn/main/output/vpn/ipv4.txt
get datacenter https://raw.githubusercontent.com/X4BNet/lists_vpn/main/output/datacenter/ipv4.txt
get tor https://check.torproject.org/torbulkexitlist

for r in "${rirs[@]}"; do
  complete_rir "$r" || { echo "$r: truncated delegation file" >&2; exit 1; }
done
if ! { at_least vpn "$min_vpn" && at_least datacenter "$min_datacenter" && at_least tor "$min_tor"; }; then
  echo "deny lists implausibly short" >&2
  exit 1
fi

# Merged country address ranges.
(cd "$work" && awk -F'|' -v cc="$COUNTRIES" '
  BEGIN { n = split(cc, c, " "); for (i = 1; i <= n; i++) want[c[i]] = 1 }
  $3 == "ipv4" && ($7 == "allocated" || $7 == "assigned") && ($2 in want) {
    split($4, o, ".")
    s = ((o[1] * 256 + o[2]) * 256 + o[3]) * 256 + o[4]
    print s, s + $5 - 1
  }' "${rirs[@]}") \
| sort -n -k1,1 \
| awk '
  function ip(x) { return sprintf("%d.%d.%d.%d", int(x / 16777216), int(x / 65536) % 256, int(x / 256) % 256, x % 256) }
  NR == 1 { s = $1; e = $2; next }
  $1 <= e + 1 { if ($2 > e) e = $2; next }
  { print ip(s) "-" ip(e); s = $1; e = $2 }
  END { if (NR) print ip(s) "-" ip(e) }' > "$work/allowed"

if ! at_least allowed 1; then
  echo "no address space for: $COUNTRIES" >&2
  exit 1
fi

cat "$work/vpn" "$work/datacenter" "$work/tor" \
| grep -E '^[0-9]{1,3}(\.[0-9]{1,3}){3}(/[0-9]{1,2})?$' > "$work/denied"

out="$STATE_DIRECTORY/lists"
mkdir -p "$out"
{
  echo "add element inet $TABLE allowed4 {"
  paste -sd, "$work/allowed"
  echo "}"
  echo "add element inet $TABLE denied4 {"
  paste -sd, "$work/denied"
  echo "}"
} > "$out/sets.nft.next"
mv "$out/sets.nft.next" "$out/sets.nft"
echo "$(wc -l < "$work/allowed") allowed ranges, $(wc -l < "$work/denied") denied networks"
