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

    Split all code into single files with short, descriptive filenames. One thing per file. Group related files into subfolders. Folder names must be short and descriptive.

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
  '';
}
