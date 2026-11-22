# shellcheck shell=bash
# Runs a PKGBUILD's functions like makepkg.

makepkgUnpackPhase() {
    runHook preUnpack
    srcdir=$PWD/src
    mkdir -p "$srcdir"
    local src name
    for src in $srcs; do
        name=$(stripHash "$src")
        if [ -d "$src" ]; then
            cp -r "$src" "$srcdir/$name"
            chmod -R u+w "$srcdir/$name"
            makepkgCheckout "$srcdir/$name"
            continue
        fi
        ln -s "$src" "$srcdir/$name"
        [[ " ${noextract-} " == *" $name "* ]] && continue
        makepkgExtract "$src" "$name"
    done
    patchShebangs --build "$srcdir" >/dev/null
    sourceRoot=src
    runHook postUnpack
}

# Fake history for git describe.
makepkgCheckout() {
    if [ -e "$1/.git" ] || ! command -v git >/dev/null; then return; fi
    export GIT_AUTHOR_DATE="@$SOURCE_DATE_EPOCH" GIT_COMMITTER_DATE="@$SOURCE_DATE_EPOCH"
    git -C "$1" init -q
    git -C "$1" add -A
    git -C "$1" -c user.name=makepkg -c user.email=makepkg@localhost commit -qm makepkg --allow-empty
    git -C "$1" -c user.name=makepkg -c user.email=makepkg@localhost tag -a "$version" -m "$version"
}

# bsdtar archives, else compressed files.
makepkgExtract() {
    if bsdtar -tf "$1" -q "*" >/dev/null 2>&1; then
        bsdtar -xf "$1" -C "$srcdir"
        return
    fi
    case "$2" in
        *.gz) gzip -dc "$1" >"$srcdir/${2%.gz}" ;;
        *.bz2) bzip2 -dc "$1" >"$srcdir/${2%.bz2}" ;;
        *.xz) xz -dc "$1" >"$srcdir/${2%.xz}" ;;
        *.zst) zstd -dcq "$1" -o "$srcdir/${2%.zst}" ;;
    esac
}

makepkgConfigurePhase() {
    runHook preConfigure
    startdir=$NIX_BUILD_TOP
    pkgdir=$NIX_BUILD_TOP/pkg
    mkdir -p "$pkgdir" "$NIX_BUILD_TOP/home" "$out"
    # Store prefixes; Zig targets Nix glibc.
    sed -E -e "s#(--(search-)?prefix[= ]|CMAKE_INSTALL_PREFIX(:PATH)?=|\\bPREFIX=|\\bprefix=)([\"']?)/usr([^/[:alnum:]_.-]|\$)#\\1\\4$out\\5#g" \
        -e "s#(-Dtarget=[^ \"']*-gnu)\\.[0-9.]+#\\1.$glibcVersion#g" \
        "$pkgbuild" >"$NIX_BUILD_TOP/PKGBUILD"
    export srcdir pkgdir startdir HOME=$NIX_BUILD_TOP/home
    # Fat LTO objects need no plugin.
    export CFLAGS="-O2 -pipe -ffat-lto-objects" CXXFLAGS="-O2 -pipe -ffat-lto-objects" LDFLAGS="" MAKEFLAGS="-j$NIX_BUILD_CORES"
    export CMAKE_POLICY_VERSION_MINIMUM=3.5
    makepkgSessionBus
    makepkgVendor
    runHook postConfigure
}

# D-Bus users get a session bus.
makepkgSessionBus() {
    command -v dbus-daemon >/dev/null || return 0
    local config
    config=$(dirname "$(command -v dbus-daemon)")/../share/dbus-1/session.conf
    DBUS_SESSION_BUS_ADDRESS=$(dbus-daemon --config-file="$config" --fork --print-address)
    export DBUS_SESSION_BUS_ADDRESS
}

# Offline package-manager caches.
makepkgVendor() {
    if [ -n "${cargoDeps-}" ]; then
        export CARGO_HOME=$NIX_BUILD_TOP/cargo
        mkdir -p "$CARGO_HOME"
        cp -r "$cargoDeps" "$NIX_BUILD_TOP/cargo-vendor"
        chmod -R u+w "$NIX_BUILD_TOP/cargo-vendor"
        substitute "$cargoDeps/.cargo/config.toml" "$CARGO_HOME/config.toml" \
            --subst-var-by vendor "$NIX_BUILD_TOP/cargo-vendor"
    fi
    if [ -n "${goModules-}" ]; then
        export GOPROXY=file://$goModules GOSUMDB=off GOTOOLCHAIN=local
        export GOPATH=$NIX_BUILD_TOP/go GOCACHE=$NIX_BUILD_TOP/go-cache
    fi
    if [ -n "${npmDeps-}" ]; then
        cp -r "$npmDeps" "$NIX_BUILD_TOP/npm-cache"
        chmod -R u+w "$NIX_BUILD_TOP/npm-cache"
        export npm_config_cache=$NIX_BUILD_TOP/npm-cache npm_config_offline=true npm_config_nodedir=$nodeDir
    fi
}

makepkgHas() {
    (
        set +u +o pipefail
        # shellcheck source=/dev/null
        source "$NIX_BUILD_TOP/PKGBUILD"
        declare -F "$1" >/dev/null
    )
}

makepkgRun() {
    echo "makepkg: $1()"
    (
        set +u +o pipefail
        # shellcheck source=/dev/null
        source "$NIX_BUILD_TOP/PKGBUILD"
        cd "$srcdir" || exit
        "$1"
    )
}

# package() expects root, as under makepkg.
makepkgPackage() {
    echo "makepkg: $1()"
    fakeroot -- bash -e -c "set +u; source \"\$NIX_BUILD_TOP/PKGBUILD\"; cd \"\$srcdir\"; \"\$0\"" "$1"
}

makepkgBuildPhase() {
    runHook preBuild
    local fn
    for fn in prepare build; do
        if makepkgHas "$fn"; then makepkgRun "$fn"; fi
    done
    runHook postBuild
}

makepkgInstallPhase() {
    runHook preInstall
    # $pkgdir/usr leads to the store.
    mkdir -p "$pkgdir$out"
    ln -s "$pkgdir$out" "$pkgdir/usr"
    makepkgPackage "package${split:+_$split}"
    makepkgMerge
    runHook postInstall
}

# Folds the FHS tree into $out.
makepkgMerge() {
    mkdir -p "$out"
    local root
    for root in "$pkgdir"/nix/store/* "$pkgdir/usr"; do
        if [ -d "$root" ] && [ ! -L "$root" ]; then cp -a "$root/." "$out/"; fi
    done
    for root in etc opt lib bin sbin; do
        if [ -d "$pkgdir/$root" ]; then cp -a "$pkgdir/$root" "$out/"; fi
    done
    if [ -d "$out/lib64" ]; then
        cp -a "$out/lib64/." "$out/lib/"
        rm -rf "${out:?}/lib64"
    fi
    rm -rf "$pkgdir" "$out/lib/.build-id"
    chmod -R u+w,go-w,ug-s "$out"
    makepkgRelink
    makepkgRetarget
}

# Absolute links follow the move.
makepkgRelink() {
    local link target moved
    while IFS= read -r -d '' link; do
        target=$(readlink "$link")
        case "$target" in
            /usr/*) moved=$out/${target#/usr/} ;;
            /opt/* | /etc/*) moved=$out$target ;;
            *) continue ;;
        esac
        if [ -e "$moved" ]; then
            ln -sfn "$moved" "$link"
            continue
        fi
        echo "makepkg: dropping link $link -> $target"
        rm "$link"
    done < <(find "$out" -type l -print0)
}

# Rewrite references to own files.
makepkgRetarget() {
    local files
    mapfile -d '' files < <(grep -rlIZE '/(usr|opt)/' "$out" || true)
    if [ ${#files[@]} -eq 0 ]; then return; fi
    MAKEPKG_OUT=$out perl -pi -e '
        s{(?<![\w.+@/-])(/(usr|opt)/[\w.+@/-]+)}{
            my ($path, $tree) = ($1, $2);
            my $moved = $ENV{MAKEPKG_OUT} . ($tree eq "usr" ? substr($path, 4) : $path);
            -e $moved ? $moved : $path
        }ge' "${files[@]}"
}
