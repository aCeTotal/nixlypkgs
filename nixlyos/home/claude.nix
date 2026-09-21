{ lib, ... }:

{
  home.activation.removeStaleClaudeMd = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    if [ -e "$HOME/.claude/CLAUDE.md" ] && [ ! -L "$HOME/.claude/CLAUDE.md" ]; then
      rm -f "$HOME/.claude/CLAUDE.md"
    fi
  '';

  home.file.".claude/CLAUDE.md".text = ''
    1. Think Before Coding

    Don't assume. Don't hide confusion. Surface tradeoffs.

    Before implementing:

    State your assumptions explicitly. If uncertain, ask.
    If multiple interpretations exist, present them - don't pick silently.
    If a simpler approach exists, say so. Push back when warranted.
    If something is unclear, stop. Name what's confusing. Ask.
    2. Simplicity First

    Minimum code that solves the problem. Nothing speculative.

    No features beyond what was asked.
    No abstractions for single-use code.
    No "flexibility" or "configurability" that wasn't requested.
    No error handling for impossible scenarios.
    If you write 200 lines and it could be 50, rewrite it.
    Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

    3. Surgical Changes

    Touch only what you must. Clean up only your own mess.

    When editing existing code:

    Don't "improve" adjacent code, comments, or formatting.
    Don't refactor things that aren't broken.
    Match existing style, even if you'd do it differently.
    If you notice unrelated dead code, mention it - don't delete it.
    When your changes create orphans:

    Remove imports/variables/functions that YOUR changes made unused.
    Don't remove pre-existing dead code unless asked.
    The test: Every changed line should trace directly to the user's request.

    4. Goal-Driven Execution

    Define success criteria. Loop until verified.

    Transform tasks into verifiable goals:

    "Add validation" → "Write tests for invalid inputs, then make them pass"
    "Fix the bug" → "Write a test that reproduces it, then make it pass"
    "Refactor X" → "Ensure tests pass before and after"
    For multi-step tasks, state a brief plan:

    1. [Step] → verify: [check]
    2. [Step] → verify: [check]
    3. [Step] → verify: [check]
    Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

    5. Never commit or push changes.

    6. File and Folder Organization

    One thing per file. Short, descriptive names. Related files grouped in short, descriptive folders.

    A file is named after the one thing it contains. No plural dumping grounds.
    No file named utils, helpers, common, misc, core, shared, lib, or stuff.
    No file over ~300 lines. If it grew past that, it holds more than one thing.
    Folder depth stays shallow - three levels from the repo root is the normal maximum.
    Folders group by feature, not by file type. Not controllers/models/views.
    A folder with one file is not a folder. A folder with twenty files is two folders.
    Name files after what they are, not when they arrived: no new, old, tmp, backup, v2, final.

    7. Comments

    Max one comment per thing. One sentence, max 5 descriptive words.
    This applies everywhere, including existing files: when touching code with longer comments, shorten them to fit this rule. This overrides "match existing style" for comments.

    8. Database Work

    All database work is done cleanly and professionally.

    No database may have artificial limitations or bottlenecks.
    Index what is queried. No N+1 queries, no unbounded scans.
    Schema changes go through proper migrations.

    9. Nix Projects

    Every nix project ships a flake:

    "nix develop" provides everything the project needs.
    "nix run" always runs the project.
    If servers are involved, they start automatically first — then the program or website pops up on its own.

    10. Performance

    Only highly efficient code, optimized for best possible performance.

    Never take the shortest path to a result — take the optimized path, with clean and efficient code.
    Prefer the least code that achieves it.

    11. Look and Feel

    Everything user-facing must look modern and professional, with tasteful eye-candy.

    12. Hash Updates (nixlypkgs)

    When asked to refresh a derivation hash, do it lightning-fast: fetch new hash, update rev/hash, done. No analysis, no questions, no extra reading.

    13. No AI Fingerprints

    Code must read like one experienced human wrote it.

    Never: banner comments, emoji, decorative separators, section headers inside code.
    Never: comments restating the line below, docstrings on obvious functions, "Note that", "This ensures that".
    Never: leftover placeholders, "rest of code unchanged", commented-out old code beside new code.
    Never: symmetric boilerplate applied everywhere - try/catch around every call, {ok, error} on every return, null checks for values that cannot be null.
    Never: names like data, result, temp, info, helper, manager, handler, utils, processX, doX, enhanced, improved, v2.
    Never: a summary paragraph at the top of a file restating what the file does.
    Never: duplicated near-identical blocks that should be a loop or a table.
    If a reviewer could name the tool that wrote it, rewrite it.

    14. Control Flow

    Flat beats nested. Always.

    No nested if statements. Invert the condition and return early.
    Max two levels of indentation inside a function body. Three means a function is missing.
    No else after return, break, or continue.
    No if/else chain longer than three arms - use a table, map, or switch on an enum.
    No boolean parameter that selects behaviour - write two functions.
    Handle the error case first; the happy path runs unindented to the end.
    No nested loops that could be hoisted, flattened, or indexed.

    15. Function and Data Shape

    One function, one job, one level of abstraction.

    A function fits on one screen. If it does not, it is doing two things.
    Three arguments or fewer. More means a struct is missing.
    One way out: no out-parameters mixed with return values.
    No stringly-typed state - enums or tagged unions.
    No magic numbers or magic strings - named constants.
    Validate at the boundary, trust inside it. No re-checking downstream.
    Plain data plus functions beats a class that exists to hold one value.

    16. Optimized Means Measured

    "Optimized" is a claim, and claims need evidence.

    Name the hot path before optimizing it.
    Allocate outside the loop, never inside. Compute invariants once.
    Contiguous arrays over pointer chasing; indices over pointers when data can move.
    No hidden work: no accidental copy, no formatting in a hot loop, no syscall per iteration.
    Right algorithm first, micro-optimization after.
    If the faster version is uglier with no measured win, keep the clear one.

    17. Definition of Done

    Done means a top-tier engineer finds nothing to change.

    Builds clean with all warnings enabled. Zero warnings, zero suppressions.
    No dead code, unused arguments, or unused imports left by your change.
    No TODO, FIXME, or stub that you introduced.
    Every line justifies itself. Delete what you cannot defend.
    Re-read the whole diff as a reviewer before reporting done. If you would comment on it, fix it first.
    Taking longer is fine. Shipping work that needs a second pass is not.

    18. Project Structure

    An experienced developer opens the repo and knows where everything is in thirty seconds.

    The root holds only what must be there: README, flake.nix, and the top-level source folders. Nothing else.
    No stray scripts, notes, logs, backups, or scratch files anywhere in the tree. Those live outside the repo.
    Every folder name says what lives in it. If you need a comment to explain the layout, the layout is wrong.
    Structure mirrors the domain, so the folder tree reads as the feature list.
    One obvious place for each kind of thing, and only one. No parallel half-migrated layouts.
    Entry points are obvious and few: one way to build, one way to run, one way to test.
    Generated and vendored output never mixes with source, and is gitignored.
    README is short: what it is, how to run it, how the tree is laid out. Nothing that will rot.
    Before finishing a task, look at the tree you leave behind. If a new developer would ask "why is this here?", move it or delete it.

    19. Gitignore

    Every project ships a .gitignore at the repo root. Only source belongs in git.

    Create it in the first commit of a new project. If a project lacks one, add it before anything else.
    Ignore all agent and LLM artifacts: .claude/, .cursor/, .aider*, .continue/, .windsurf/, .codeium/, .github/copilot*, *.agent.md, chat and session logs, plan/summary/analysis notes, and any scratch file an assistant produced.
    Ignore build output, generated code, and vendored dependencies: result, result-*, build/, dist/, target/, node_modules/, .venv/, __pycache__/, *.o, *.so.
    Ignore secrets and local config: .env, .env.*, *.key, *.pem, *.local, local settings files.
    Ignore editor and OS junk: .idea/, .vscode/, *.swp, .DS_Store, Thumbs.db.
    Ignore caches and logs: .cache/, *.log, coverage/, .direnv/.
    Keep it curated and short: entries for what this project actually produces, not a copied 300-line template. No blanket wildcards that hide real source.
    Never commit a file the .gitignore is meant to catch, and never force-add one.
    A tracked file that should be ignored is a bug: say so, and fix the ignore rule.
  '';
}
