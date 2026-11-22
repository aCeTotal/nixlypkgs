export function shortSha(sha: string | null | undefined) {
  return sha ? sha.slice(0, 10) : "–";
}
