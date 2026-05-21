import { normalizeTimestampToUtcIso } from './time.ts';

Deno.test('normalizeTimestampToUtcIso converts explicit offset to UTC', () => {
  const result = normalizeTimestampToUtcIso(
    '2026-05-21T16:50:00+07:00',
    420,
  );

  if (result !== '2026-05-21T09:50:00.000Z') {
    throw new Error(`Expected UTC timestamp, got ${result}`);
  }
});

Deno.test('normalizeTimestampToUtcIso treats offsetless value as user local time', () => {
  const result = normalizeTimestampToUtcIso(
    '2026-05-21T16:50:00',
    420,
  );

  if (result !== '2026-05-21T09:50:00.000Z') {
    throw new Error(`Expected UTC timestamp, got ${result}`);
  }
});
