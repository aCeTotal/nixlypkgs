{ module }:

{ pkgs, lib, ... }:

let
  demoRepo = pkgs.callPackage ./demo-repo.nix { };
in
{
  name = "cachepanel";

  nodes.server = {
    imports = [ module ];

    services.nixly-cachepanel = {
      enable = true;
      source = {
        seed = "file:///var/lib/demo";
        sshRemote = "cachepanel@localhost:source.git";
      };
      # Missing on purpose: the update must fail cleanly.
      selfUpdate = {
        flake = "/var/lib/demo-server";
        host = "demo";
      };
    };

    nix.settings = {
      substituters = lib.mkForce [ ];
      experimental-features = [ "nix-command" "flakes" ];
    };

    services.openssh.enable = true;

    environment.systemPackages = [ pkgs.curl pkgs.git pkgs.gnutar pkgs.gzip pkgs.openssl pkgs.unzip ];

    systemd.services.demo-repo = {
      wantedBy = [ "multi-user.target" ];
      before = [ "nixly-cachepanel.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "cachepanel";
        StateDirectory = "demo";
      };
      script = "${lib.getExe demoRepo} /var/lib/demo";
    };

    virtualisation = {
      memorySize = 4096;
      cores = 4;
      diskSize = 8192;
    };
  };

  testScript = ''
    import base64
    import json

    panel = "http://127.0.0.1:8686"

    server.wait_for_unit("nixly-cachepanel.service")
    server.wait_for_open_port(8686)

    def status(command):
        return server.succeed(f"curl -s -o /dev/null -w '%{{http_code}}' {command}").strip()

    with subtest("login is required and rate limited per account"):
        assert status(f"{panel}/api/packages") == "401"
        assert status(f"-X POST -H 'Content-Type: application/json' -d '{{\"username\":\"nixlyos\",\"password\":\"feil\"}}' {panel}/api/auth/login") == "401"
        login = json.loads(server.succeed(
            f"curl -fsS -c /tmp/jar -X POST -H 'Content-Type: application/json' "
            f"-d '{{\"username\":\"nixlyos\",\"password\":\"nixos\"}}' {panel}/api/auth/login"))
        csrf = login["csrf"]
        assert status(f"-b /tmp/jar -X POST {panel}/api/watcher/poll") == "403"

    def get(path):
        return json.loads(server.succeed(f"curl -fsS -b /tmp/jar {panel}/api{path}"))

    def send(path, body="{}", method="POST"):
        encoded = base64.b64encode(body.encode()).decode()
        return server.succeed(
            f"echo {encoded} | base64 -d | curl -fsS -b /tmp/jar -X {method} -H 'X-Cachepanel-CSRF: {csrf}' "
            f"-H 'Content-Type: application/json' --data-binary @- {panel}/api{path}")

    def packages():
        return {p["attr"]: p for p in get("/packages")}

    def settled(attr, count):
        versions = packages().get(attr, {}).get("versions", [])
        return len(versions) == count and all(v["state"] == "cached" for v in versions)

    def head():
        return server.succeed("runuser -u cachepanel -- git -C /var/lib/demo rev-parse HEAD").strip()

    push = "GIT_SSH_COMMAND='ssh -o StrictHostKeyChecking=no' git -c safe.directory=/var/lib/demo -C /var/lib/demo push --quiet"

    def source_head():
        return server.succeed("runuser -u cachepanel -- git -C /var/lib/cachepanel/source.git rev-parse main").strip()

    # The panel commits too; follow it before adding a demo commit.
    def bump():
        server.succeed("runuser -u cachepanel -- git -C /var/lib/demo fetch --quiet /var/lib/cachepanel/source.git main")
        server.succeed("runuser -u cachepanel -- git -C /var/lib/demo reset --quiet --hard FETCH_HEAD")
        server.succeed("runuser -u cachepanel -- ${lib.getExe demoRepo} /var/lib/demo bump")
        server.succeed(f"{push} cachepanel@localhost:source.git HEAD:main")
        send("/watcher/poll")

    with subtest("history fills three versions per package and builds them"):
        send("/watcher/poll")
        retry(lambda _: settled("hello-demo", 3) and settled("clock-demo", 3) and settled("steady-demo", 1), timeout_seconds=600)
        assert packages()["hello-demo"]["versions"][0]["commit"] == head()

    with subtest("the panel owns the source: SSH pushes, HTTPS clones, history only grows"):
        source = get("/source")
        assert source == {"clone": f"{panel}/source.git", "remote": "cachepanel@localhost:source.git", "keys": []}, source
        server.succeed("ssh-keygen -q -t ed25519 -N ''' -f /root/.ssh/id_ed25519")
        server.succeed("runuser -u cachepanel -- ${lib.getExe demoRepo} /var/lib/demo bump")
        server.fail(f"{push} cachepanel@localhost:source.git HEAD:main")
        public_key = server.succeed("cat /root/.ssh/id_ed25519.pub").strip()
        added = json.loads(send("/source/keys", json.dumps({"name": "test", "publicKey": public_key})))
        assert added["type"] == "ssh-ed25519" and added["fingerprint"].startswith("SHA256:"), added
        server.fail("ssh -o StrictHostKeyChecking=no cachepanel@localhost true")
        server.succeed(f"{push} cachepanel@localhost:source.git HEAD:main")
        assert source_head() == head()
        server.fail(f"{push} --force cachepanel@localhost:source.git HEAD~1:main")
        server.fail(f"{push} cachepanel@localhost:source.git :main")
        server.succeed("runuser -u cachepanel -- git -C /var/lib/demo -c user.name=Demo -c user.email=demo@nixly.invalid "
                       "commit --quiet --allow-empty --allow-empty-message -m '''")
        server.fail(f"{push} cachepanel@localhost:source.git HEAD:main")
        server.succeed("runuser -u cachepanel -- git -C /var/lib/demo reset --quiet --hard HEAD~1")
        assert source_head() == head()
        server.succeed(f"git clone --quiet {panel}/source.git /tmp/clone")
        assert server.succeed("git -C /tmp/clone rev-parse HEAD").strip() == head()
        server.fail(f"git -C /tmp/clone push --quiet {panel}/source.git HEAD:refs/heads/other")
        server.succeed(f"nix flake metadata 'git+{panel}/source.git?rev={head()}'")
        send("/watcher/poll")
        retry(lambda _: settled("hello-demo", 3) and packages()["hello-demo"]["versions"][0]["commit"] == head(), timeout_seconds=300)

    with subtest("a new commit is cached and the oldest version evicted"):
        oldest = packages()["hello-demo"]["versions"][-1]["id"]
        evicted = get("/packages/hello-demo")["versions"][-1]["outputs"]["out"].removeprefix("/nix/store/")[:32]
        bump()
        retry(lambda _: settled("hello-demo", 3) and packages()["hello-demo"]["versions"][0]["commit"] == head(), timeout_seconds=300)
        assert oldest not in [v["id"] for v in packages()["hello-demo"]["versions"]]
        server.succeed(f"test ! -e /var/lib/cachepanel/gcroots/{oldest}")

    with subtest("a selected version survives rotation"):
        pinned = packages()["hello-demo"]["versions"][-1]["id"]
        send("/packages/hello-demo/selection", json.dumps({"versionId": pinned}), "PUT")
        bump()
        retry(lambda _: packages()["hello-demo"]["versions"][0]["commit"] == head() and settled("hello-demo", 4), timeout_seconds=300)
        kept = [v["id"] for v in packages()["hello-demo"]["versions"]]
        assert pinned in kept and len(kept) == 4, kept

    with subtest("modules come from the source's catalogue, in import order"):
        modules = get("/modules")["modules"]
        assert [m["slug"] for m in modules] == ["system", "security", "network", "session", "audio", "user",
                                                "gaming", "apps", "desktop", "htpc", "server", "hardware"], modules
        assert {m["slug"] for m in modules if m["required"]} == {"system", "security", "network", "user", "hardware"}
        assert all(m["lines"] == 1 and m["changedAt"] for m in modules), modules
        assert get("/modules/gaming")["source"] == "{ ... }: { }\n"
        assert {u["name"] for u in get("/modules/system")["usedBy"]} == {"desktop", "htpc", "server"}
        server.fail("runuser -u postgres -- psql -d cachepanel -c 'SELECT 1 FROM modules'")
        problem = json.loads(send("/modules/validate", json.dumps({"source": "{ a = ; }"})))
        assert problem["line"] == 1 and problem["column"] == 7, problem

    def profile(name):
        return next(p for p in get("/profiles") if p["name"] == name)

    def approve(awaiting, derivations=()):
        return json.dumps({"profiles": [{"id": p["id"], "tree": p["testingTree"], "rev": p["testingRev"]} for p in awaiting],
                           "derivations": [{"attr": d["attr"], "version": d["version"]} for d in derivations]})

    def approval_status(body):
        return status(f"-b /tmp/jar -X POST -H 'X-Cachepanel-CSRF: {csrf}' -H 'Content-Type: application/json' -d '{body}' {panel}/api/approval")

    with subtest("profiles are seeded, checked and land in testing"):
        retry(lambda _: all(p["testingTree"] for p in get("/profiles")), timeout_seconds=300)
        assert {p["name"] for p in get("/profiles")} == {"desktop", "htpc", "server"}
        assert all(p["stableTree"] is None for p in get("/profiles"))
        assert status(f"{panel}/api/v1/profiles/desktop") == "404"
        assert status(f"{panel}/api/v1/profiles/desktop/testing") == "200"
        def tree(name, path):
            return next(f["content"] for f in get(f"/profiles/{name}")["files"] if f["path"] == path)

        assert sorted(f["path"] for f in get("/profiles/desktop")["files"]) == ["default.nix", "modules.nix", "pins.nix"]
        assert "hello-demo" in tree("desktop", "pins.nix")
        assert "imports" not in tree("desktop", "default.nix")
        chosen = tree("desktop", "modules.nix")
        assert all(f'"{slug}"' in chosen for slug in ("session", "audio", "desktop")) and '"htpc"' not in chosen, chosen
        assert '"system"' not in chosen, chosen
        assert '"htpc"' in tree("htpc", "modules.nix") and '"desktop"' not in tree("htpc", "modules.nix")
        headless = tree("server", "modules.nix")
        assert '"server"' in headless and '"session"' not in headless and '"audio"' not in headless, headless
        desktop = get("/profiles/desktop")
        assert {m["slug"] for m in desktop["modules"] if m["selected"]} >= {"system", "session", "desktop"}, desktop["modules"]

    with subtest("stable moves only on an approval of everything reviewed"):
        def tested(profile):
            return profile["checkState"] in ("passed", "skipped") and (profile["candidateTree"], profile["candidateRev"]) == (profile["testingTree"], profile["testingRev"])

        retry(lambda _: all(tested(p) for p in get("/profiles")), timeout_seconds=300)
        review = get("/approval")
        awaiting = review["profiles"]
        assert {p["name"] for p in awaiting} == {"desktop", "htpc", "server"}, awaiting
        desktop = next(p for p in awaiting if p["name"] == "desktop")
        assert {"path": "modules.nix", "change": "added"} in desktop["files"], desktop
        assert approval_status(approve(awaiting[:1])) == "409"
        stale = [dict(p, testingRev="0" * 40) for p in awaiting]
        assert approval_status(approve(stale)) == "409"
        assert all(p["stableTree"] is None for p in get("/profiles"))
        approved = {p["id"]: (p["testingTree"], p["testingRev"]) for p in awaiting}
        send("/approval", approve(awaiting, review["derivations"]))
        retry(lambda _: all((p["stableTree"], p["stableRev"]) == approved[p["id"]] for p in get("/profiles")), timeout_seconds=60)
        retry(lambda _: status(f"{panel}/api/v1/profiles/desktop") == "200", timeout_seconds=60)
        assert json.loads(server.succeed(f"curl -fsS {panel}/api/v1/profiles/desktop/stable"))["branch"] == "stable"

    with subtest("editing a module is a commit that only reaches testing"):
        module = get("/modules/apps")
        stable = (profile("desktop")["stableTree"], profile("desktop")["stableRev"])
        body = json.dumps({"base": module["head"], "slug": "apps", "title": module["title"], "description": "Edited in the panel",
                           "source": module["source"] + "# edited\n", "required": False})
        unsigned = base64.b64encode(body.encode()).decode()
        assert status(f"-b /tmp/jar -X PUT -H 'X-Cachepanel-CSRF: {csrf}' -H 'Content-Type: application/json' "
                      f"--data-binary \"$(echo {unsigned} | base64 -d)\" {panel}/api/modules/apps") == "422"
        body = json.dumps(dict(json.loads(body), message="apps: mark as edited"))
        edited = json.loads(send("/modules/apps", body, "PUT"))["sha"]
        assert source_head() == edited
        module = get("/modules/apps")
        assert module["source"].endswith("# edited\n") and module["description"] == "Edited in the panel", module
        assert module["history"][0]["sha"] == edited and module["history"][0]["subject"] == "apps: mark as edited", module["history"]
        assert get(f"/modules/apps/revisions/{module['history'][1]['sha']}")["source"] == "{ ... }: { }\n"
        stale = base64.b64encode(body.encode()).decode()
        assert status(f"-b /tmp/jar -X PUT -H 'X-Cachepanel-CSRF: {csrf}' -H 'Content-Type: application/json' "
                      f"--data-binary \"$(echo {stale} | base64 -d)\" {panel}/api/modules/apps") == "409"
        retry(lambda _: any(p["name"] == "desktop" and p["testingRev"] == edited for p in get("/approval")["profiles"]), timeout_seconds=300)
        assert (profile("desktop")["stableTree"], profile("desktop")["stableRev"]) == stable
        assert any(c["sha"] == edited for c in get("/approval")["commits"])

    with subtest("machines read both branches with ETag and immutable trees"):
        server.succeed(f"curl -fsS -D /tmp/headers -o /tmp/pointer {panel}/api/v1/profiles/desktop")
        etag = server.succeed("grep -i '^etag:' /tmp/headers | cut -d' ' -f2 | tr -d '\\r'").strip()
        assert status(f"-H 'If-None-Match: {etag}' {panel}/api/v1/profiles/desktop") == "304"
        pointer = json.loads(server.succeed("cat /tmp/pointer"))
        assert pointer["source"] == f"git+{panel}/source.git?rev={pointer['rev']}", pointer
        server.succeed(f"curl -fsS {panel}{pointer['path']} | tar -tz tree/default.nix")
        testing = json.loads(server.succeed(f"curl -fsS {panel}/api/v1/profiles/desktop/testing"))
        assert testing["branch"] == "testing" and (testing["tree"], testing["rev"]) != (pointer["tree"], pointer["rev"]), (testing, pointer)
        assert status(f"{panel}/api/v1/profiles/desktop/nightly") == "404"
        branches = {p["name"]: (p["stable"], p["testing"]) for p in json.loads(server.succeed(f"curl -fsS {panel}/api/v1/profiles"))}
        assert branches["desktop"] == (True, True), branches

    def stable_pins(name):
        pointer = json.loads(server.succeed(f"curl -fsS {panel}/api/v1/profiles/{name}/stable"))
        return server.succeed(f"curl -fsS {panel}{pointer['path']} | tar -xzO tree/pins.nix")

    with subtest("each derivation reaches stable on its own"):
        send("/packages/hello-demo/selection", json.dumps({"versionId": None}), "PUT")
        retry(lambda _: any(d["attr"] == "hello-demo" for d in get("/approval")["derivations"]), timeout_seconds=300)
        newest = next(d for d in get("/approval")["derivations"] if d["attr"] == "hello-demo")
        assert approval_status(json.dumps({"profiles": [], "derivations": [{"attr": "hello-demo", "version": 1}]})) == "409"
        base = profile("desktop")["stableRev"]
        send("/approval", approve([], [newest]))
        out = next(v for v in get("/packages/hello-demo")["versions"] if v["id"] == newest["version"])["outputs"]["out"]
        retry(lambda _: out in stable_pins("desktop"), timeout_seconds=300)
        assert profile("desktop")["stableRev"] == base
        assert get("/packages/hello-demo")["stableVersionId"] == newest["version"]
        assert all(d["attr"] != "hello-demo" for d in get("/approval")["derivations"])
        assert get("/approval")["profiles"], "the base still waits"

    with subtest("the NixlyOS CA anchors module signing and the Secure Boot chain"):
        assert status(f"{panel}/api/v1/ca.pem") == "404" and get("/trust")["active"] is None
        ca = json.loads(send("/trust/ca"))
        server.succeed(f"curl -fsS -o /tmp/ca.der {panel}/api/v1/ca.der")
        server.succeed(f"sha256sum /tmp/ca.der | grep -q {ca['fingerprint']}")
        server.succeed(f"curl -fsS {panel}/api/v1/ca.pem | openssl x509 -noout -ext extendedKeyUsage | grep -q 'Code Signing'")
        server.succeed(f"stat -c '%a %U' /var/lib/cachepanel/signing/{ca['fingerprint']}.key | grep -qx '600 cachepanel'")
        server.succeed(f"curl -fsS -b /tmp/jar -o /tmp/epic.zip {panel}/api/trust/epic.zip")
        server.succeed("unzip -l /tmp/epic.zip | grep -q policy.json")
        firmware = get("/trust")["firmware"]
        assert [d["variable"] for d in firmware] == ["PK", "KEK", "db"], firmware
        assert [c["owner"] for c in firmware[0]["certs"]] == ["NixlyOS"], firmware
        assert sum(c["owner"] == "Microsoft" for c in firmware[2]["certs"]) == 5, firmware
        for variable in ["PK", "KEK", "db"]:
            server.succeed(f"curl -fsS -o /tmp/{variable}.auth {panel}/api/v1/secureboot/setup/{variable}.auth")
        server.succeed("tail -c $(stat -c %s /tmp/ca.der) /tmp/PK.auth | cmp - /tmp/ca.der")
        assert status(f"{panel}/api/v1/secureboot/setup/dbx.auth") == "404"
        assert status(f"{panel}/api/v1/secureboot/{'0' * 64}/PK.auth") == "404"
        send("/trust/ca")
        server.succeed(f"curl -fsS -o /tmp/rotate.auth {panel}/api/v1/secureboot/{ca['fingerprint']}/PK.auth")
        server.fail("tail -c $(stat -c %s /tmp/ca.der) /tmp/rotate.auth | cmp -s - /tmp/ca.der")
        trust = get("/trust")
        assert trust["active"]["fingerprint"] != ca["fingerprint"] and len(trust["history"]) == 2, trust
        assert sum(c["owner"] == "NixlyOS" for c in trust["firmware"][2]["certs"]) == 2, trust["firmware"]

    with subtest("uploaded sources are served to machines and analysed"):
        server.succeed("head -c 4096 /dev/urandom > /tmp/blob.bin")
        uploaded = json.loads(server.succeed(
            f"curl -fsS -b /tmp/jar -H 'X-Cachepanel-CSRF: {csrf}' -F file=@/tmp/blob.bin {panel}/api/sources"))
        server.succeed(f"curl -fsS {panel}/api/v1/sources/{uploaded['hash']}/blob.bin | cmp - /tmp/blob.bin")
        recipe = json.loads(send("/recipes", json.dumps({"origin": "upload", "upload": uploaded["hash"]})))
        retry(lambda _: get(f"/recipes/{recipe['id']}")["state"] == "failed", timeout_seconds=120)
        assert "file type" in get(f"/recipes/{recipe['id']}")["error"]
        send(f"/recipes/{recipe['id']}", method="DELETE")
        assert get("/recipes") == []

    with subtest("the cache is its own signed directory and drops evicted versions"):
        out = get("/packages/hello-demo")["versions"][0]["outputs"]["out"]
        narinfo = out.removeprefix("/nix/store/")[:32]
        server.succeed(f"test -f /var/lib/cachepanel/cache/{narinfo}.narinfo")
        server.succeed(f"curl -fsS {panel}/nix-cache-info | grep -q 'WantMassQuery: 1'")
        server.succeed(f"curl -fsS {panel}/{narinfo}.narinfo | grep -q 'Sig: cache.aceclan.no-1:'")
        nar_hash = server.succeed(f"curl -fsS {panel}/{narinfo}.narinfo | sed -n 's/^NarHash: sha256://p'").strip()
        server.succeed(f"curl -fsS -o /dev/null '{panel}/nar/{nar_hash}.nar?hash={narinfo}'")
        server.succeed(f"nix store verify --store {panel} --option trusted-public-keys \"$(cat /var/lib/nixly-cache/keys/cache-pub.key)\" {out}")
        server.wait_until_succeeds("journalctl -u nixly-cachepanel | grep -q '\"msg\":\"garbage collection\"'", timeout=120)
        server.wait_until_succeeds(f"test ! -e /var/lib/cachepanel/cache/{evicted}.narinfo", timeout=120)
        server.fail("journalctl -u nixly-cachepanel | grep '\"level\":\"WARN\",\"msg\":\"garbage collection\"'")

    with subtest("a profile picks its kernel and settings from the source's catalogue"):
        assert get("/kernels")["performance"]["settings"]["tickRate"]["default"] == "1000"
        def save(settings):
            detail = get("/profiles/desktop")
            kept = {key: detail["profile"][key] for key in ("name", "title", "description", "platform", "pinnedSha", "modules", "packages")}
            body = json.dumps(kept | {"kernel": "performance", "kernelSettings": settings, "base": detail["head"], "message": "desktop: tune the kernel"})
            return status(f"-b /tmp/jar -X PUT -H 'X-Cachepanel-CSRF: {csrf}' -H 'Content-Type: application/json' "
                          f"-d '{body}' {panel}/api/profiles/desktop")

        assert save({"tickRate": "250"}) == "422" and save({"scheduler": "bore"}) == "422"
        assert save({"tickRate": "1000"}) == "422", "the default alone changes nothing"
        assert save({"tickRate": "300"}) == "201"
        assert get("/profiles/desktop")["profile"]["kernelSettings"] == {"tickRate": "300"}
        assert '"tickRate": "300"' in get("/source/file?path=nixlyos/profiles/desktop.json")["text"]
        assert get("/source/log?path=nixlyos/profiles/desktop.json")["commits"][0]["subject"] == "desktop: tune the kernel"
        retry(lambda _: any('"tickRate" = "300";' in f["content"] for f in get("/profiles/desktop")["files"]), timeout_seconds=300)

    with subtest("an idle server asks root for the new panel once, and a failed update is not retried"):
        update = get("/update")
        assert update["configured"] and update["enabled"], update
        retry(lambda _: get("/update")["newest"] is not None, timeout_seconds=300)
        newest = get("/update")["newest"]
        assert newest["out"] != update["running"] and newest["out"].endswith("-cachepanel-demo"), (newest, update)
        server.wait_until_succeeds("test -n \"$(find /var/lib/cachepanel/update/idle -newermt '-60 seconds')\"", timeout=180)
        request = json.loads(server.wait_until_succeeds("cat /var/lib/cachepanel/update/request.json", timeout=120))
        assert request["target"] == newest["out"], request
        retry(lambda _: (get("/update")["status"] or {}).get("phase") == "failed", timeout_seconds=120)
        assert "stopped at line" in get("/update")["status"]["log"], get("/update")
        written = server.succeed("stat -c %Y /var/lib/cachepanel/update/request.json")
        server.sleep(35)
        assert server.succeed("stat -c %Y /var/lib/cachepanel/update/request.json") == written
        send("/update", json.dumps({"enabled": False}), method="PUT")
        assert not get("/update")["enabled"]

    with subtest("the panel edits the source: commit, history, diff and revert"):
        head = get("/source/tree")["head"]
        assert head == source_head()
        note = {"path": "docs/notes.md", "content": "hello\n"}
        created = json.loads(send("/source/commits", json.dumps({"base": head, "message": "Add notes", "changes": [note]})))
        assert source_head() == created["sha"]
        assert get("/source/file?path=docs/notes.md")["text"] == "hello\n"
        stale = json.dumps({"base": head, "message": "stale", "changes": [note]})
        assert status(f"-b /tmp/jar -X POST -H 'X-Cachepanel-CSRF: {csrf}' -H 'Content-Type: application/json' "
                      f"-d '{stale}' {panel}/api/source/commits") == "409"
        details = get(f"/source/commits/{created['sha']}")
        assert details["files"][0]["path"] == "docs/notes.md" and "+hello" in details["files"][0]["patch"], details
        assert get("/source/log?path=docs/notes.md")["commits"][0]["sha"] == created["sha"]
        reverted = json.loads(send(f"/source/commits/{created['sha']}/revert", json.dumps({"base": created["sha"], "message": "Drop notes"})))
        assert status(f"-b /tmp/jar {panel}/api/source/file?path=docs/notes.md") == "404"
        author = server.succeed("runuser -u cachepanel -- git -C /var/lib/cachepanel/source.git log -1 --format=%an").strip()
        assert author == "nixlyos", author
        retry(lambda _: any(c["sha"] == reverted["sha"] for c in get("/commits")["items"]), timeout_seconds=120)

    with subtest("inputs update into a flake.lock commit"):
        assert get("/source/inputs")["inputs"] == []
        server.succeed("mkdir -p /var/lib/demo-extra && echo 1 > /var/lib/demo-extra/value")
        flake = get("/source/file?path=flake.nix")
        declared = flake["text"].replace("outputs = { self }:", 'inputs.extra = { url = "path:/var/lib/demo-extra"; flake = false; };\n  outputs = { self, ... }:')
        send("/source/commits", json.dumps({"base": flake["head"], "message": "Add an input", "changes": [{"path": "flake.nix", "content": declared}]}))
        send("/source/inputs/update", json.dumps({"base": get("/source/inputs")["head"], "inputs": [], "message": "Lock inputs"}))
        extra = next(i for i in get("/source/inputs")["inputs"] if i["name"] == "extra")
        assert extra["source"] == "/var/lib/demo-extra", extra
        locked = get("/source/file?path=flake.lock")["text"]
        server.succeed("echo 2 > /var/lib/demo-extra/value")
        send("/source/inputs/update", json.dumps({"base": get("/source/inputs")["head"], "inputs": ["extra"], "message": "Update extra"}))
        assert get("/source/file?path=flake.lock")["text"] != locked
        same = json.dumps({"base": get("/source/inputs")["head"], "inputs": ["extra"], "message": "Update extra"})
        assert status(f"-b /tmp/jar -X POST -H 'X-Cachepanel-CSRF: {csrf}' -H 'Content-Type: application/json' "
                      f"-d '{same}' {panel}/api/source/inputs/update") == "422"
        assert get("/source/log?path=flake.lock")["commits"][0]["subject"] == "Update extra"

    with subtest("the editor completes from the newest revision and formats Nix"):
        index = json.loads(server.succeed(f"curl -fsS --compressed -b /tmp/jar {panel}/api/editor/nix"))
        assert index["options"][0]["name"] == "nixlyos.demo.enable" and "hello-demo" in index["packages"], index
        tag = server.succeed(f"curl -fsS -o /dev/null -D - -b /tmp/jar {panel}/api/editor/nix | grep -i '^etag:' | cut -d' ' -f2 | tr -d '\\r'").strip()
        assert status(f"-b /tmp/jar -H 'If-None-Match: {tag}' {panel}/api/editor/nix") == "304"
        assert json.loads(send("/editor/format", json.dumps({"source": "{a=1;}"}))) == {"source": "{ a = 1; }\n", "error": ""}
        assert json.loads(send("/editor/format", json.dumps({"source": "{ a = ; }"})))["error"] == 'unexpected "; }", expecting expression'

    with subtest("profiles are files in the source and testing follows their commits"):
        lab = {"name": "lab", "title": "Lab", "description": "", "platform": "desktop", "base": source_head()}
        assert status(f"-b /tmp/jar -X POST -H 'X-Cachepanel-CSRF: {csrf}' -H 'Content-Type: application/json' "
                      f"-d '{json.dumps(lab)}' {panel}/api/profiles") == "422"
        created = json.loads(send("/profiles", json.dumps(lab | {"message": "profiles: add lab"})))
        assert json.loads(get("/source/file?path=nixlyos/profiles/lab.json")["text"])["title"] == "Lab"
        assert "lab" in {p["name"] for p in get("/profiles")}
        retry(lambda _: profile("lab")["candidateTree"] is not None, timeout_seconds=300)
        send("/profiles/lab", json.dumps({"base": created["sha"], "message": "profiles: drop lab"}), "DELETE")
        assert "lab" not in {p["name"] for p in get("/profiles")}
        retry(lambda _: server.succeed("runuser -u postgres -- psql -d cachepanel -At -c \"SELECT count(*) FROM profiles WHERE name = 'lab'\"").strip() == "0",
              timeout_seconds=300)

    with subtest("each derivation follows its upstream into testing, and stable waits for its approval"):
        def upstream_commit(value, subject):
            server.succeed(f"echo {value} > /tmp/tracked/value",
                           f"git -C /tmp/tracked add value && git -C /tmp/tracked -c user.name=Up -c user.email=up@up commit --quiet -m '{subject}'",
                           "git -C /tmp/tracked push --quiet /var/lib/upstream/tracked.git main",
                           "chmod -R a+rX /var/lib/upstream")
            return server.succeed("git -C /tmp/tracked rev-parse HEAD").strip()

        def output(attr):
            return server.succeed(f"cat {get(f'/packages/{attr}')['versions'][0]['outputs']['out']}").strip()

        server.succeed("git init --quiet --bare --initial-branch=main /var/lib/upstream/tracked.git",
                       "git init --quiet --initial-branch=main /tmp/tracked")
        first = upstream_commit(1, "Start at one")
        url = "file:///var/lib/upstream/tracked.git"
        pinned = json.loads(server.succeed(f"nix flake prefetch --option flake-registry ''' --json 'git+{url}?rev={first}'"))["hash"]
        tracked = {"url": url, "branch": "main", "rev": first, "hash": pinned, "version": "1"}
        send("/source/commits", json.dumps({"base": source_head(), "message": "Track the demo upstream",
                                            "changes": [{"path": "pkgs/tracked-demo/source.json", "content": json.dumps(tracked)}]}))
        retry(lambda _: settled("tracked-demo", 1) and output("tracked-demo") == "1", timeout_seconds=300)
        second = upstream_commit(2, "Count to two")
        send("/upstream/check")
        retry(lambda _: json.loads(get("/source/file?path=pkgs/tracked-demo/source.json")["text"])["rev"] == second, timeout_seconds=120)
        bump = get("/source/log?path=pkgs/tracked-demo/source.json")["commits"][0]
        assert bump["subject"].startswith("tracked-demo: 1 → 20") and bump["author"] == "nixly-panel", bump
        assert "Count to two" in get(f"/source/commits/{bump['sha']}")["body"]
        retry(lambda _: settled("tracked-demo", 2) and output("tracked-demo") == "2", timeout_seconds=300)
        follows = next(u for u in get("/upstream") if u["attr"] == "tracked-demo")
        assert follows["state"] == "current" and follows["latestRev"] == second and follows["committedAt"], follows
        waiting = next(d for d in get("/approval")["derivations"] if d["attr"] == "tracked-demo")
        assert waiting["stableVersion"] is None, waiting
  '';
}
