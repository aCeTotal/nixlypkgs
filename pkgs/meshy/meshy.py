import argparse
import json
import sys
from pathlib import Path
from urllib.parse import urlencode

from client import ApiError, data_uri, download, request, save_key, wait

TEXT = "/v2/text-to-3d"
IMAGE = "/v1/image-to-3d"
RIG = "/v1/rigging"
ANIMATION = "/v1/animations"
RETEXTURE = "/v1/retexture"
TYPE_PATHS = {
    "text-to-3d-preview": TEXT,
    "text-to-3d-refine": TEXT,
    "image-to-3d": IMAGE,
    "rig": RIG,
    "animate": ANIMATION,
    "retexture": RETEXTURE,
}
MODELS = ("meshy-6-lite", "meshy-6", "meshy-7.1", "latest")


def model_source(src):
    if Path(src).is_file():
        return {"model_url": data_uri(src)}
    return {"input_task_id": src}


def image_source(src):
    return data_uri(src) if Path(src).is_file() else src


def geometry(args):
    body = {"topology": "quad" if args.quad else "triangle", "pose_mode": args.pose or ""}
    if args.model:
        body["ai_model"] = args.model
    if args.polycount:
        body["should_remesh"] = True
        body["target_polycount"] = args.polycount
    return body


def texturing(args):
    body = {"enable_pbr": args.pbr}
    if args.texture_prompt:
        body["texture_prompt"] = args.texture_prompt
    return body


def glb_url(task):
    done = task.get("result") or {}
    return done.get("rigged_character_glb_url") or done.get("animation_glb_url") or task["model_urls"]["glb"]


def summary(task, out):
    report = {"task_id": task["id"], "path": download(glb_url(task), out), "credits": task["consumed_credits"]}
    if task.get("thumbnail_url"):
        report["thumbnail_url"] = task["thumbnail_url"]
    basic = (task.get("result") or {}).get("basic_animations")
    if basic:
        report["walking_glb_url"] = basic["walking_glb_url"]
        report["running_glb_url"] = basic["running_glb_url"]
    return report


def submit(path, body):
    return wait(path, request("POST", path, body)["result"])


def refine(preview_id, args):
    body = {"mode": "refine", "preview_task_id": preview_id, **texturing(args)}
    report = summary(submit(TEXT, body), args.out)
    report["preview_task_id"] = preview_id
    return report


def cmd_text(args):
    preview = submit(TEXT, {"mode": "preview", "prompt": args.prompt, **geometry(args)})
    if args.preview_only:
        return summary(preview, args.out)
    report = refine(preview["id"], args)
    report["credits"] += preview["consumed_credits"]
    return report


def cmd_refine(args):
    return refine(args.task_id, args)


def cmd_image(args):
    body = {"image_url": image_source(args.image), **geometry(args), **texturing(args)}
    return summary(submit(IMAGE, body), args.out)


def cmd_rig(args):
    body = {"height_meters": args.height, **model_source(args.source)}
    return summary(submit(RIG, body), args.out)


def cmd_animate(args):
    body = {"rig_task_id": args.rig_task_id, "action_ids": args.action_ids}
    return summary(submit(ANIMATION, body), args.out)


def cmd_animations(args):
    query = urlencode({k: v for k, v in (("search", args.search), ("category", args.category)) if v})
    library = request("GET", f"{ANIMATION}/library" + (f"?{query}" if query else ""))
    return [{"action_id": a["action_id"], "name": a["name"], "category": a["category"]} for a in library]


def cmd_retexture(args):
    body = {"enable_pbr": args.pbr, **model_source(args.source)}
    if args.prompt:
        body["text_style_prompt"] = args.prompt
    if args.image:
        body["image_style_url"] = image_source(args.image)
    return summary(submit(RETEXTURE, body), args.out)


def cmd_fetch(args):
    kind = request("GET", f"{IMAGE}/{args.task_id}")["type"]
    if kind not in TYPE_PATHS:
        raise ApiError(0, f"unsupported task type {kind}")
    return summary(wait(TYPE_PATHS[kind], args.task_id), args.out)


def cmd_balance(args):
    return request("GET", "/v1/balance")


def cmd_key(args):
    return {"key_file": str(save_key(args.key))}


def build_parser():
    out = argparse.ArgumentParser(add_help=False)
    out.add_argument("-o", "--out", required=True, help="destination .glb path")
    shape = argparse.ArgumentParser(add_help=False)
    shape.add_argument("--pose", choices=("a-pose", "t-pose"), help="character pose, required before rigging")
    shape.add_argument("--quad", action="store_true", help="quad topology instead of triangles")
    shape.add_argument("--polycount", type=int, help="remesh to this many polygons (100-300000)")
    shape.add_argument("--model", choices=MODELS, help="Meshy model, default latest")
    texture = argparse.ArgumentParser(add_help=False)
    texture.add_argument("--pbr", action="store_true", help="metallic/roughness/normal maps")
    texture.add_argument("--texture-prompt", help="guides texturing, max 800 chars")

    parser = argparse.ArgumentParser(prog="meshy", description="Meshy.ai 3D asset generation")
    sub = parser.add_subparsers(dest="command", required=True)

    text = sub.add_parser("text", parents=[out, shape, texture], help="text prompt to textured GLB")
    text.add_argument("prompt")
    text.add_argument("--preview-only", action="store_true", help="untextured mesh only, refine later")
    text.set_defaults(run=cmd_text)

    ref = sub.add_parser("refine", parents=[out, texture], help="texture a preview task")
    ref.add_argument("task_id")
    ref.set_defaults(run=cmd_refine)

    image = sub.add_parser("image", parents=[out, shape, texture], help="image file or URL to textured GLB")
    image.add_argument("image")
    image.set_defaults(run=cmd_image)

    rig = sub.add_parser("rig", parents=[out], help="auto-rig a humanoid (task id or .glb)")
    rig.add_argument("source")
    rig.add_argument("--height", type=float, default=1.7, help="character height in meters")
    rig.set_defaults(run=cmd_rig)

    animate = sub.add_parser("animate", parents=[out], help="apply library actions to a rig task")
    animate.add_argument("rig_task_id")
    animate.add_argument("action_ids", type=int, nargs="+", help="1-10 ids from `meshy animations`")
    animate.set_defaults(run=cmd_animate)

    library = sub.add_parser("animations", help="list animation library actions")
    library.add_argument("--search")
    library.add_argument("--category", choices=("WalkAndRun", "BodyMovements", "DailyActions", "Fighting", "Dancing"))
    library.set_defaults(run=cmd_animations)

    retex = sub.add_parser("retexture", parents=[out], help="new textures for a task id or .glb")
    retex.add_argument("source")
    style = retex.add_mutually_exclusive_group(required=True)
    style.add_argument("--prompt", help="texture style description")
    style.add_argument("--image", help="style reference image file or URL")
    retex.add_argument("--pbr", action="store_true")
    retex.set_defaults(run=cmd_retexture)

    fetch = sub.add_parser("fetch", parents=[out], help="wait for any task and download its GLB")
    fetch.add_argument("task_id")
    fetch.set_defaults(run=cmd_fetch)

    sub.add_parser("balance", help="remaining credits").set_defaults(run=cmd_balance)
    key = sub.add_parser("key", help="store the API key")
    key.add_argument("key")
    key.set_defaults(run=cmd_key)
    return parser


def main():
    args = build_parser().parse_args()
    try:
        report = args.run(args)
    except ApiError as err:
        sys.exit(f"meshy: {err}")
    print(json.dumps(report))


if __name__ == "__main__":
    main()
