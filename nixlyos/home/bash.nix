{ pkgs, config, ... }:

{
    home.packages = [ pkgs.eza ];

    # Bash
    programs = {
        bash = {
            enable = true;
            enableCompletion = true;

            shellAliases = {
                "z" = "zoxide";
                "pfo" = "cd /mnt/nfs/Bigdisk1/www/PFO";
                "work" = "cd /mnt/nfs/Bigdisk1/Work/painting";
                ".." = "cd ..";
                "ls" = "eza --long --all --header --group --git --icons --color=always";
            };

            # push: add everything, prompt for a message, commit and push.
            initExtra = ''
                push() {
                    local msg
                    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
                        echo "push: not a git repo" >&2
                        return 1
                    fi
                    git add -A
                    if git diff --cached --quiet; then
                        echo "push: nothing new to commit, pushing existing commits"
                        git push
                        return
                    fi
                    read -rep "commit> " msg || return 1
                    if [ -z "$msg" ]; then
                        echo "push: empty message, aborted" >&2
                        git reset -q
                        return 1
                    fi
                    git commit -m "$msg" && git push
                }

                # pull: fast-forward to upstream, only when the remote is ahead and the tree is clean.
                pull() {
                    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
                        echo "pull: not a git repo" >&2
                        return 1
                    fi
                    if [ -n "$(git status --porcelain)" ]; then
                        echo "pull: uncommitted changes, aborted" >&2
                        return 1
                    fi
                    git fetch || return 1
                    local behind
                    behind=$(git rev-list --count HEAD..@{u} 2>/dev/null)
                    if [ -z "$behind" ]; then
                        echo "pull: no upstream branch" >&2
                        return 1
                    fi
                    if [ "$behind" -eq 0 ]; then
                        echo "pull: already up to date"
                        return 0
                    fi
                    git pull --ff-only
                }

                # hash: print the fetchFromGitHub fields for the repo's pushed HEAD.
                hash() {
                    local url owner_repo rev sha sri
                    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
                        echo "hash: not a git repo" >&2
                        return 1
                    fi
                    url=$(git remote get-url origin 2>/dev/null)
                    if [ -z "$url" ]; then
                        echo "hash: no origin remote" >&2
                        return 1
                    fi
                    owner_repo=''${url#git@github.com:}
                    owner_repo=''${owner_repo#https://github.com/}
                    owner_repo=''${owner_repo%.git}
                    rev=$(git rev-parse HEAD)
                    if [ "$(git rev-parse @{u} 2>/dev/null)" != "$rev" ]; then
                        echo "hash: warning — HEAD differs from upstream, run push first" >&2
                    fi
                    echo "prefetching $owner_repo @ ''${rev:0:7} ..." >&2
                    sha=$(nix-prefetch-url --unpack \
                        "https://github.com/$owner_repo/archive/$rev.tar.gz" 2>/dev/null)
                    if [ -z "$sha" ]; then
                        echo "hash: prefetch failed (is $rev pushed to github?)" >&2
                        return 1
                    fi
                    sri=$(nix hash convert --hash-algo sha256 --to sri "$sha" 2>/dev/null \
                        || nix hash to-sri --type sha256 "$sha")
                    echo "owner = \"''${owner_repo%%/*}\";"
                    echo "repo = \"''${owner_repo##*/}\";"
                    echo "rev = \"$rev\";"
                    echo "hash = \"$sri\";"
                }

                # auto-pull: ff-only, and a silent no-op offline or without an upstream.
                _auto_pull() {
                    [ -n "$(git status --porcelain 2>/dev/null)" ] && return 0
                    git fetch -q 2>/dev/null || return 0
                    local behind
                    behind=$(git rev-list --count HEAD..@{u} 2>/dev/null)
                    [ -z "$behind" ] || [ "$behind" -eq 0 ] && return 0
                    if git pull --ff-only -q >/dev/null 2>&1; then
                        echo "auto-pull: $behind new commit(s)"
                    fi
                }

                # Run _auto_pull once when the prompt lands in a new git repo.
                _git_enter_hook() {
                    local top
                    top=$(git rev-parse --show-toplevel 2>/dev/null)
                    if [ -n "$top" ] && [ "$top" != "$_LAST_GIT_TOP" ]; then
                        _auto_pull
                    fi
                    _LAST_GIT_TOP=$top
                }
                PROMPT_COMMAND="_git_enter_hook''${PROMPT_COMMAND:+;$PROMPT_COMMAND}"

                # direnv only on editor launch, never on cd, via `direnv exec`.
                nvim() {
                    local top
                    top=$(git rev-parse --show-toplevel 2>/dev/null)
                    [ -n "$top" ] && _auto_pull
                    if [ -n "$top" ] && [ -e "$top/flake.nix" ]; then
                        if [ ! -e "$top/.envrc" ]; then
                            printf 'use flake\n' > "$top/.envrc"
                            direnv allow "$top"
                        fi
                        direnv exec "$top" nvim "$@"
                    else
                        command nvim "$@"
                    fi
                }
            '';
        };
        direnv = {
            enable = true;
            # No shell hook: only the nvim wrapper's `direnv exec` loads the env.
            enableBashIntegration = false;
            nix-direnv.enable = true;
            # Auto-approve .envrc in own repos so direnv never asks.
            config.whitelist.prefix = [ "${config.home.homeDirectory}/git" ];
        };
    };
}
