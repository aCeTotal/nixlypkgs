const relative = new Intl.RelativeTimeFormat("en-GB", { numeric: "auto" });
const absolute = new Intl.DateTimeFormat("en-GB", { dateStyle: "medium", timeStyle: "short" });

const steps: [Intl.RelativeTimeFormatUnit, number][] = [
  ["second", 60],
  ["minute", 60],
  ["hour", 24],
  ["day", 30],
  ["month", 12],
  ["year", Infinity],
];

export function timeAgo(iso: string | null | undefined) {
  if (!iso) return "never";
  let value = (new Date(iso).getTime() - Date.now()) / 1000;
  for (const [unit, size] of steps) {
    if (Math.abs(value) < size) return relative.format(Math.round(value), unit);
    value /= size;
  }
  return absolute.format(new Date(iso));
}

export function dateTime(iso: string | null | undefined) {
  return iso ? absolute.format(new Date(iso)) : "–";
}
