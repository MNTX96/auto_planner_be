export type QuillDeltaOp = Record<string, unknown>;
export type QuillDelta = QuillDeltaOp[];

export function deltaFromPlainText(text: string | null | undefined): QuillDelta {
  return [{ insert: `${text ?? ''}\n` }];
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function isDeltaOp(value: unknown): value is QuillDeltaOp {
  if (!isRecord(value)) {
    return false;
  }
  return 'insert' in value || 'retain' in value || 'delete' in value;
}

function ensureDocumentNewline(delta: QuillDelta): QuillDelta {
  if (delta.length === 0) {
    return deltaFromPlainText('');
  }

  const last = delta[delta.length - 1];
  if (typeof last.insert === 'string' && last.insert.endsWith('\n')) {
    return delta;
  }
  if (typeof last.insert === 'string') {
    return [
      ...delta.slice(0, -1),
      { ...last, insert: `${last.insert}\n` },
    ];
  }
  return [...delta, { insert: '\n' }];
}

export function normalizeQuillDelta(
  value: unknown,
  fallbackText = '',
): QuillDelta {
  if (Array.isArray(value) && value.length > 0 && value.every(isDeltaOp)) {
    return ensureDocumentNewline(value);
  }
  return deltaFromPlainText(fallbackText);
}

export function plainTextFromDelta(delta: QuillDelta): string {
  return delta
    .map((op) => typeof op.insert === 'string' ? op.insert : '')
    .join('')
    .replace(/\n$/, '');
}
