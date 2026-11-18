# Package changes between two systems.

# Store paths to "name<TAB>version", output/variant suffix dropped.
split_names() {
  awk '{
    p = substr($0, 45)
    if (!match(p, /-[0-9]/)) next
    v = substr(p, RSTART + 1); sub(/-[a-zA-Z][a-zA-Z0-9]*$/, "", v)
    print substr(p, 1, RSTART - 1) "\t" v
  }'
}

# Closure as "name<TAB>v1 v2 ...", one line per name.
versions() {
  split_names < "$1" | LC_ALL=C sort -u |
    awk -F '\t' '
      $1 != prev { if (prev != "") print prev "\t" vs; prev = $1; vs = $2; next }
      { vs = vs " " $2 }
      END { if (prev != "") print prev "\t" vs }'
}

# Names the user installed: system and home packages, kernel.
installed() {
  local roots
  mapfile -t roots < <(readlink -f "$1/sw"; grep -- '-home-manager-path$' "$2")
  { nix-store -q --references "${roots[@]}"; dirname "$(readlink -f "$1/kernel")"; } |
    split_names | cut -f1
}

# $1: dir with old.paths, new.paths, pinned; $2, $3: systems.
print_changes() {
  versions "$1/old.paths" > "$1/old.tsv"
  versions "$1/new.paths" > "$1/new.tsv"
  { installed "$2" "$1/old.paths"; installed "$3" "$1/new.paths"; } > "$1/installed"
  LC_ALL=C join -t $'\t' -a1 -a2 -e '' -o 0,1.2,2.2 "$1/old.tsv" "$1/new.tsv" |
    awk -F '\t' -v top="$1/installed" -v pinned="$1/pinned" \
      -v G="$GRN" -v Y="$YLW" -v D="$DIM" -v B="$BLD" -v N="$RST" '
      function vcmp(a, b,   x, y, n, i) {
        n = split(a, x, /[^0-9]+/); i = split(b, y, /[^0-9]+/); if (i > n) n = i
        for (i = 1; i <= n; i++) if (x[i] + 0 != y[i] + 0) return x[i] + 0 < y[i] + 0 ? -1 : 1
        return 0
      }
      # Versions in $1 missing from $2; newest goes to top.
      function only(a, b,   x, y, i, s) {
        split(b, x, " "); delete y
        for (i in x) y[x[i]] = 1
        split(a, x, " "); s = ""; top = ""
        for (i = 1; i in x; i++) {
          if (x[i] in y) continue
          s = s (s == "" ? "" : ", ") x[i]
          if (top == "" || vcmp(x[i], top) > 0) top = x[i]
        }
        return s
      }
      function add(sec, name, from, to) {
        rows[sec] = rows[sec] name "\t" from "\t" to "\n"
        if (length(name) > w) w = length(name)
        if (to != "" && length(from) > v) v = length(from)
      }
      function show(sec,   n, i, f, l) {
        n = split(rows[sec], l, "\n")
        for (i = 1; i < n; i++) {
          split(l[i], f, "\t")
          if (f[3] == "") printf "    %s %-*s  %s%s%s\n", sym[sec], w, f[1], from[sec], f[2], N
          else printf "    %s %-*s  %s%-*s%s  %s%s%s\n", sym[sec], w, f[1], from[sec], v, f[2], N, to[sec], f[3], N
        }
      }
      BEGIN {
        split("up down new gone kept", order, " ")
        sym["up"] = G "↑" N; from["up"] = D; to["up"] = D "→ " N G
        sym["down"] = Y "↓" N; from["down"] = D; to["down"] = D "→ " N Y
        sym["new"] = G "+" N; from["new"] = G
        sym["gone"] = D "−" N; from["gone"] = D
        sym["kept"] = Y "!" N; to["kept"] = D
        while ((getline l < top) > 0) user[l] = 1
        while ((getline l < pinned) > 0) {
          split(l, f, "\t"); kept[f[1]] = 1
          add("kept", f[1], f[2], f[3] " feilet")
        }
      }
      $2 == $3 || ($1 in kept) || $1 ~ /^nixos-system-/ { next }
      !($1 in user) { deps++; next }
      {
        gone = only($2, $3); was = top
        came = only($3, $2); now = top
      }
      gone == "" { add("new", $1, came); next }
      came == "" { add("gone", $1, gone); next }
      vcmp(was, now) > 0 { add("down", $1, gone, came); next }
      { add("up", $1, gone, came) }
      END {
        if (w == 0 && deps == 0) exit
        printf "\n  %sEndringer%s\n", B, N
        for (i = 1; i <= 5; i++) show(order[i])
        if (deps) printf "    %s· %d %s endret%s\n", D, deps, deps == 1 ? "avhengighet" : "avhengigheter", N
        print ""
      }'
}
