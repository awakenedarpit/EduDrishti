export function formatDate(value: string, options: Intl.DateTimeFormatOptions = { dateStyle: "medium" }) {
  return new Intl.DateTimeFormat(undefined, options).format(new Date(value));
}

export function formatShortDate(value: string) {
  return formatDate(value, { month: "short", day: "numeric", year: "numeric" });
}
