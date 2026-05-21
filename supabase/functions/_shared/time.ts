const explicitTimezonePattern = /(z|[+-]\d{2}:?\d{2})$/i;

export function formatTimezoneOffset(offsetMinutes: number): string {
  const sign = offsetMinutes >= 0 ? '+' : '-';
  const absOffset = Math.abs(offsetMinutes);
  const hours = String(Math.floor(absOffset / 60)).padStart(2, '0');
  const minutes = String(absOffset % 60).padStart(2, '0');
  return `${sign}${hours}:${minutes}`;
}

export function toOffsetIsoString(date: Date, offsetMinutes: number): string {
  const localDate = new Date(date.getTime() + offsetMinutes * 60 * 1000);
  const timestamp = localDate.toISOString().replace('Z', '');
  return `${timestamp}${formatTimezoneOffset(offsetMinutes)}`;
}

export function normalizeTimestampToUtcIso(
  value: unknown,
  offsetMinutes: number,
): string {
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new Error('Timestamp is required');
  }

  const raw = value.trim();
  const timestamp = explicitTimezonePattern.test(raw)
    ? raw
    : `${raw}${formatTimezoneOffset(offsetMinutes)}`;
  const date = new Date(timestamp);
  if (Number.isNaN(date.getTime())) {
    throw new Error(`Invalid timestamp: ${raw}`);
  }
  return date.toISOString();
}
