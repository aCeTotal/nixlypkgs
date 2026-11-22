const units = ["B", "kB", "MB", "GB", "TB"];
const step = 1024;

export function formatBytes(bytes: number | null | undefined) {
  if (bytes == null) return "–";
  let value = bytes;
  let unit = 0;
  while (value >= step && unit < units.length - 1) {
    value /= step;
    unit++;
  }
  return `${value.toLocaleString("nb-NO", { maximumFractionDigits: value < 10 ? 1 : 0 })} ${units[unit]}`;
}
