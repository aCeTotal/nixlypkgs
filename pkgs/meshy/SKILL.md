---
name: meshy
description: Generate real 3D assets with the `meshy` CLI (Meshy.ai) - game-ready meshes, props, humanoid characters, auto-rigging and animations, delivered as GLB and ready for Bevy. Use whenever a Bevy or other 3D project needs a model, character, prop, mesh, texture or animation; never hand-build geometry or leave placeholder cubes when a real asset is wanted.
---

# Meshy 3D assets

`meshy` is on PATH. It talks to the Meshy.ai API with the key in
`~/.local/nixlyos/meshy.key` (or `MESHY_API_KEY`). Every command prints one
JSON line on stdout with `task_id`, `path` and `credits`; progress goes to
stderr. Generation takes 1-5 minutes, so run it with a 600000 ms Bash
timeout. If a call is cut off, `meshy fetch <task_id> -o <path>` resumes the
wait and downloads the result; results stay on Meshy for 3 days.

Missing key: `meshy key msy_...`. Check credits first: `meshy balance`.

## Commands

```
meshy text "<prompt>" -o assets/models/<name>.glb [--pose t-pose|a-pose] [--pbr]
      [--polycount N] [--quad] [--model meshy-6-lite|meshy-6|meshy-7.1|latest]
      [--texture-prompt "<style>"] [--preview-only]
meshy refine <preview_task_id> -o <path>.glb [--pbr] [--texture-prompt "<style>"]
meshy image <file|url> -o <path>.glb [same options as text]
meshy rig <task_id|file.glb> -o <path>.glb [--height 1.7]
meshy animations [--search walk] [--category WalkAndRun|BodyMovements|DailyActions|Fighting|Dancing]
meshy animate <rig_task_id> <action_id>... -o <path>.glb
meshy retexture <task_id|file.glb> --prompt "<style>" | --image <file|url> -o <path>.glb [--pbr]
meshy fetch <task_id> -o <path>.glb
meshy balance
```

Credits (approximate): text preview 20, refine 10, image 30, retexture 10,
rig 5, animate 3 per action. Pass a task id rather than a file to `rig` and
`retexture` when the source came from meshy: it skips the upload.

## Workflow

Props and scenery: one `meshy text` call. Write the prompt like an art
brief: subject, style, materials, era, "game asset, clean silhouette".
Keep `--polycount` to the budget of the scene (props 2000-8000, hero
characters 10000-30000). Add `--pbr` when the scene uses realistic lighting.

Characters: generate with `--pose t-pose` (or a-pose), rig, then animate.

```
meshy text "stylized knight, full plate armor, game character" --pose t-pose -o assets/models/knight.glb
meshy rig <task_id from above> -o assets/models/knight_rigged.glb
meshy animations --search idle
meshy animate <rig task_id> 4 92 -o assets/models/knight_anims.glb
```

`rig` also reports `walking_glb_url` and `running_glb_url`; fetch them with
`curl -o` when the character needs locomotion. `animate` returns one GLB with
every requested action as a separate clip, in the order the ids were given
and named after the action (`Idle`, `Casual_Walk`).

To check a result visually, download `thumbnail_url` to the scratchpad and
Read it.

## Bevy

Meshy GLB files are self-contained (textures embedded), in meters, origin at
the feet. Load scenes and clips with glTF labels:

```rust
#[derive(Resource)]
struct KnightAnims { graph: Handle<AnimationGraph>, idle: AnimationNodeIndex }

fn setup(mut commands: Commands, assets: Res<AssetServer>, mut graphs: ResMut<Assets<AnimationGraph>>) {
    let clip = assets.load(GltfAssetLabel::Animation(0).from_asset("models/knight_anims.glb"));
    let (graph, idle) = AnimationGraph::from_clip(clip);
    commands.insert_resource(KnightAnims { graph: graphs.add(graph), idle });
    commands.spawn(SceneRoot(assets.load(GltfAssetLabel::Scene(0).from_asset("models/knight_rigged.glb"))));
}

fn play(mut commands: Commands, anims: Res<KnightAnims>, mut players: Query<(Entity, &mut AnimationPlayer), Added<AnimationPlayer>>) {
    for (entity, mut player) in &mut players {
        commands.entity(entity).insert(AnimationGraphHandle(anims.graph.clone()));
        player.play(anims.idle).repeat();
    }
}
```

Clips from the animation GLB target the same bone names as the rigged
scene, so they can drive it directly. Static props need only the `SceneRoot`
line. Never commit the API key or `~/.local/nixlyos/meshy.key` contents.
