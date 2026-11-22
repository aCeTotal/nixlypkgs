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

    with subtest("the module registry is sorted into categories"):
        catalog = get("/catalog")
        assert [c["name"] for c in catalog["categories"]] == ["system", "apps", "hardware"], catalog
        modules = {m["name"]: m for m in catalog["modules"]}
        assert modules["mode"]["required"] and modules["gpu/demo"]["automatic"], modules

    with subtest("profiles are seeded, checked and published"):
        retry(lambda _: any(p["name"] == "desktop" and p["publishedTree"] for p in get("/profiles")), timeout_seconds=300)
        assert {p["name"] for p in get("/profiles")} == {"desktop", "laptop", "htpc"}
        desktop = get("/profiles/desktop")
        paths = [f["path"] for f in desktop["files"]]
        assert "default.nix" in paths and "pins.nix" in paths and "profile.json" in paths, paths
        pins = next(f["content"] for f in desktop["files"] if f["path"] == "pins.nix")
        assert "hello-demo" in pins, pins
        chosen = json.loads(next(f["content"] for f in desktop["files"] if f["path"] == "profile.json"))["modules"]
        assert chosen == ["mode", "demo-app"], chosen

    with subtest("machines read pointers with ETag and immutable trees"):
        server.succeed(f"curl -fsS -D /tmp/headers -o /tmp/pointer {panel}/api/v1/profiles/desktop")
        etag = server.succeed("grep -i '^etag:' /tmp/headers | cut -d' ' -f2 | tr -d '\\r'").strip()
        assert status(f"-H 'If-None-Match: {etag}' {panel}/api/v1/profiles/desktop") == "304"
        pointer = json.loads(server.succeed("cat /tmp/pointer"))
        server.succeed(f"curl -fsS {panel}{pointer['path']} | tar -tz | grep -q tree/default.nix")

    with subtest("uploaded sources are served to machines and analysed"):
        server.succeed("head -c 4096 /dev/urandom > /tmp/blob.bin")
        uploaded = json.loads(server.succeed(
            f"curl -fsS -b /tmp/jar -H 'X-Cachepanel-CSRF: {csrf}' -F file=@/tmp/blob.bin {panel}/api/sources"))
        server.succeed(f"curl -fsS {panel}/api/v1/sources/{uploaded['hash']}/blob.bin | cmp - /tmp/blob.bin")
        recipe = json.loads(send("/recipes", json.dumps({"origin": "upload", "upload": uploaded["hash"]})))
        retry(lambda _: get(f"/recipes/{recipe['id']}")["state"] == "failed", timeout_seconds=120)
        assert "filtypen" in get(f"/recipes/{recipe['id']}")["error"]
        send(f"/recipes/{recipe['id']}", method="DELETE")
        assert get("/recipes") == []

    with subtest("the cache serves and garbage collection runs unprivileged"):
        detail = get("/packages/hello-demo")["versions"][0]["outputs"]["out"]
        narinfo = detail.removeprefix("/nix/store/").split("-")[0]
        server.succeed(f"curl -fsS http://127.0.0.1:5002/{narinfo}.narinfo | grep -q StorePath")
        server.wait_until_succeeds("journalctl -u nixly-cachepanel | grep -q '\"msg\":\"garbage collection\"'", timeout=120)
        server.fail("journalctl -u nixly-cachepanel | grep '\"level\":\"WARN\",\"msg\":\"garbage collection\"'")
  '';
}
