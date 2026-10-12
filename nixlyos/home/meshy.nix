{ pkgs, ... }:

{
  home.packages = [ pkgs.meshy ];
  home.file.".claude/skills/meshy/SKILL.md".source = "${pkgs.meshy}/share/meshy/SKILL.md";
}
