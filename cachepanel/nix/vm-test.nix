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
      repository = "file:///var/lib/demo";
    };

    nix.settings = {
      substituters = lib.mkForce [ ];
      experimental-features = [ "nix-command" "flakes" ];
    };

    environment.systemPackages = [ pkgs.curl pkgs.git pkgs.gnutar pkgs.gzip ];

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
        return server.succeed(
            f"curl -fsS -b /tmp/jar -X {method} -H 'X-Cachepanel-CSRF: {csrf}' "
            f"-H 'Content-Type: application/json' -d '{body}' {panel}/api{path}")

    def packages():
        return {p["attr"]: p for p in get("/packages")}

    def settled(attr, count):
        versions = packages().get(attr, {}).get("versions", [])
        return len(versions) == count and all(v["state"] == "cached" for v in versions)

    def head():
        return server.succeed("runuser -u cachepanel -- git -C /var/lib/demo rev-parse HEAD").strip()

    def bump():
        server.succeed("runuser -u cachepanel -- ${lib.getExe demoRepo} /var/lib/demo bump")
        send("/watcher/poll")

    with subtest("history fills three versions per package and builds them"):
        send("/watcher/poll")
        retry(lambda _: settled("hello-demo", 3) and settled("clock-demo", 3) and settled("steady-demo", 1), timeout_seconds=600)
        assert packages()["hello-demo"]["versions"][0]["commit"] == head()

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

    with subtest("every module lives in the database, in import order"):
        modules = get("/modules")
        assert [m["slug"] for m in modules] == ["system", "security", "network", "session", "audio", "user",
                                                "gaming", "apps", "desktop", "htpc", "server", "hardware"], modules
        assert {m["slug"] for m in modules if m["required"]} == {"system", "security", "network", "user", "hardware"}
        problem = json.loads(send("/modules/validate", json.dumps({"source": "{ a = ; }"})))
        assert problem["line"] == 1 and problem["column"] == 7, problem

    def profile(name):
        return next(p for p in get("/profiles") if p["name"] == name)

    def approve(awaiting):
        return json.dumps({"profiles": [{"id": p["id"], "tree": p["testingTree"], "rev": p["testingRev"]} for p in awaiting]})

    def approval_status(body):
        return status(f"-b /tmp/jar -X POST -H 'X-Cachepanel-CSRF: {csrf}' -H 'Content-Type: application/json' -d '{body}' {panel}/api/approval")

    with subtest("profiles are seeded, checked and land in testing"):
        retry(lambda _: all(p["testingTree"] for p in get("/profiles")), timeout_seconds=300)
        assert {p["name"] for p in get("/profiles")} == {"desktop", "htpc", "server"}
        assert all(p["stableTree"] is None for p in get("/profiles"))
        assert status(f"{panel}/api/v1/profiles/desktop") == "404"
        assert status(f"{panel}/api/v1/profiles/desktop/testing") == "200"
        desktop = get("/profiles/desktop")
        paths = [f["path"] for f in desktop["files"]]
        assert "default.nix" in paths and "pins.nix" in paths and "modules/desktop.nix" in paths, paths
        assert "modules/htpc.nix" not in paths, paths
        pins = next(f["content"] for f in desktop["files"] if f["path"] == "pins.nix")
        assert "hello-demo" in pins, pins
        imports = next(f["content"] for f in desktop["files"] if f["path"] == "default.nix")
        assert imports.index("./modules/system.nix") < imports.index("./modules/hardware.nix"), imports
        htpc = [f["path"] for f in get("/profiles/htpc")["files"]]
        assert "modules/htpc.nix" in htpc and "modules/desktop.nix" not in htpc, htpc
        headless = [f["path"] for f in get("/profiles/server")["files"]]
        assert "modules/server.nix" in headless and "modules/session.nix" not in headless and "modules/audio.nix" not in headless, headless
        assert "modules/session.nix" in paths and "modules/audio.nix" in paths, paths

    with subtest("stable moves only on an approval of everything reviewed"):
        retry(lambda _: all(p["checkState"] in ("passed", "skipped") for p in get("/profiles")), timeout_seconds=300)
        awaiting = get("/approval")["profiles"]
        assert {p["name"] for p in awaiting} == {"desktop", "htpc", "server"}, awaiting
        desktop = next(p for p in awaiting if p["name"] == "desktop")
        assert {"path": "modules/desktop.nix", "change": "added"} in desktop["files"], desktop
        assert approval_status(approve(awaiting[:1])) == "409"
        stale = [dict(p, testingRev="0" * 40) for p in awaiting]
        assert approval_status(approve(stale)) == "409"
        assert all(p["stableTree"] is None for p in get("/profiles"))
        send("/approval", approve(awaiting))
        assert get("/approval")["profiles"] == []
        assert all(p["stableTree"] == p["testingTree"] and p["stableRev"] == p["testingRev"] for p in get("/profiles"))
        retry(lambda _: status(f"{panel}/api/v1/profiles/desktop") == "200", timeout_seconds=60)
        assert json.loads(server.succeed(f"curl -fsS {panel}/api/v1/profiles/desktop/stable"))["branch"] == "stable"

    with subtest("editing a module keeps revisions and only reaches testing"):
        apps = next(m for m in get("/modules") if m["slug"] == "apps")
        module = get(f"/modules/{apps['id']}")
        before = profile("desktop")["testingTree"]
        body = json.dumps({"slug": "apps", "title": module["title"], "description": module["description"],
                           "source": module["source"] + "# edited\n", "required": False})
        server.succeed(f"echo {base64.b64encode(body.encode()).decode()} | base64 -d > /tmp/edit.json")
        server.succeed(
            f"curl -fsS -b /tmp/jar -X PUT -H 'X-Cachepanel-CSRF: {csrf}' "
            f"-H 'Content-Type: application/json' -d @/tmp/edit.json {panel}/api/modules/{apps['id']}")
        assert get(f"/modules/{apps['id']}")["revision"] == 2
        retry(lambda _: profile("desktop")["testingTree"] not in (None, before), timeout_seconds=300)
        files = get("/profiles/desktop")["files"]
        assert next(f["content"] for f in files if f["path"] == "modules/apps.nix").endswith("# edited\n")
        assert profile("desktop")["stableTree"] == before
        awaiting = get("/approval")["profiles"]
        desktop = next(p for p in awaiting if p["name"] == "desktop")
        assert desktop["files"] == [{"path": "modules/apps.nix", "change": "changed"}], desktop

    with subtest("machines read both branches with ETag and immutable trees"):
        server.succeed(f"curl -fsS -D /tmp/headers -o /tmp/pointer {panel}/api/v1/profiles/desktop")
        etag = server.succeed("grep -i '^etag:' /tmp/headers | cut -d' ' -f2 | tr -d '\\r'").strip()
        assert status(f"-H 'If-None-Match: {etag}' {panel}/api/v1/profiles/desktop") == "304"
        pointer = json.loads(server.succeed("cat /tmp/pointer"))
        server.succeed(f"curl -fsS {panel}{pointer['path']} | tar -tz tree/default.nix")
        testing = json.loads(server.succeed(f"curl -fsS {panel}/api/v1/profiles/desktop/testing"))
        assert testing["branch"] == "testing" and testing["tree"] != pointer["tree"], (testing, pointer)
        assert status(f"{panel}/api/v1/profiles/desktop/nightly") == "404"
        branches = {p["name"]: (p["stable"], p["testing"]) for p in json.loads(server.succeed(f"curl -fsS {panel}/api/v1/profiles"))}
        assert branches["desktop"] == (True, True), branches

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
  '';
}
