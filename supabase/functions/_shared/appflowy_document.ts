export type JsonRecord = Record<string, unknown>;

export interface AppFlowyDocument {
  document: {
    type: 'page';
    data?: JsonRecord;
    children: JsonRecord[];
  };
}

export const noteBlockIdAttribute = '_note_block_id';
export const noteRootBlockId = 'root';

function isRecord(value: unknown): value is JsonRecord {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function paragraphNode(text: string): JsonRecord {
  return {
    type: 'paragraph',
    data: {
      [noteBlockIdAttribute]: crypto.randomUUID(),
      delta: [{ insert: text }],
    },
  };
}

export function documentFromPlainText(
  text: string | null | undefined,
): AppFlowyDocument {
  const lines = (text ?? '').split('\n');
  return {
    document: {
      type: 'page',
      data: {
        [noteBlockIdAttribute]: noteRootBlockId,
      },
      children: lines.map(paragraphNode),
    },
  };
}

export function normalizeAppFlowyBlockIds(
  document: AppFlowyDocument,
): AppFlowyDocument {
  const normalizeNode = (node: JsonRecord, isRoot = false): JsonRecord => {
    const data = isRecord(node.data) ? { ...node.data } : {};
    data[noteBlockIdAttribute] = isRoot
      ? noteRootBlockId
      : typeof data[noteBlockIdAttribute] === 'string' &&
          data[noteBlockIdAttribute].trim().length > 0
        ? data[noteBlockIdAttribute]
        : crypto.randomUUID();
    const children = Array.isArray(node.children)
      ? node.children.filter(isRecord).map((child) => normalizeNode(child))
      : [];
    return {
      type: typeof node.type === 'string' ? node.type : 'paragraph',
      data,
      ...(children.length > 0 ? { children } : {}),
    };
  };

  const root = normalizeNode(document.document, true);
  return {
    document: {
      type: 'page',
      data: root.data as JsonRecord,
      children: Array.isArray(root.children)
        ? (root.children as JsonRecord[])
        : [],
    },
  };
}

export function normalizeAppFlowyDocument(
  value: unknown,
  fallbackText = '',
): AppFlowyDocument {
  if (isRecord(value) && isRecord(value.document)) {
    const document = value.document;
    if (document.type === 'page' && Array.isArray(document.children)) {
      return normalizeAppFlowyBlockIds(value as unknown as AppFlowyDocument);
    }
  }
  if (typeof value === 'string') {
    return normalizeAppFlowyBlockIds(documentFromPlainText(value));
  }
  return normalizeAppFlowyBlockIds(documentFromPlainText(fallbackText));
}

export function plainTextFromDocument(document: AppFlowyDocument): string {
  const lines: string[] = [];
  for (const node of document.document.children) {
    const data = isRecord(node.data) ? node.data : {};
    const delta = Array.isArray(data.delta) ? data.delta : [];
    const text = delta
      .map((op) =>
        isRecord(op) && typeof op.insert === 'string' ? op.insert : ''
      )
      .join('');
    lines.push(text);
  }
  return lines.join('\n').trim();
}
