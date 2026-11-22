const minute = 60;
const hour = 60 * minute;

export function formatDuration(seconds: number | null | undefined) {
  if (seconds == null) return "–";
  const whole = Math.max(0, Math.round(seconds));
  if (whole < minute) return `${whole} s`;
  if (whole < hour) return `${Math.floor(whole / minute)} min ${whole % minute} s`;
  return `${Math.floor(whole / hour)} t ${Math.floor((whole % hour) / minute)} min`;
}

export function secondsBetween(from: string | null, to: string | null) {
  if (!from || !to) return null;
  return (new Date(to).getTime() - new Date(from).getTime()) / 1000;
}
