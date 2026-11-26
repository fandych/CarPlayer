import { PlistNode } from './PlistNode';

const SENSITIVE_PLIST_KEY: RegExp =
  /(password|passphrase|shared.?secret|private.?key|challenge|signature|credential|token|authorization|certificate|device.?id|mac.?address|session.*uuid)/i;
const MAX_PLIST_DIAGNOSTIC_DEPTH: number = 4;
const MAX_PLIST_DIAGNOSTIC_ITEMS: number = 16;
const MAX_PLIST_DIAGNOSTIC_STRING: number = 128;

export function formatPlistDiagnostic(root: PlistNode): string {
  return formatPlistNodeDiagnostic(root, '', 0);
}

function formatPlistNodeDiagnostic(node: PlistNode, key: string, depth: number): string {
  if (SENSITIVE_PLIST_KEY.test(key)) {
    return '[REDACTED]';
  }
  if (depth >= MAX_PLIST_DIAGNOSTIC_DEPTH &&
    (node.kind === 'array' || node.kind === 'dictionary')) {
    const count = node.kind === 'array' ? node.arrayValue.length : node.dictionaryValue.size;
    return `<${node.kind} ${count} items>`;
  }
  switch (node.kind) {
    case 'null':
      return 'null';
    case 'boolean':
      return node.boolValue ? 'true' : 'false';
    case 'integer':
      return node.integerValue.toString();
    case 'real':
      return String(node.realValue);
    case 'data':
      return `<data ${node.dataValue.length}B>`;
    case 'string': {
      const truncated = node.stringValue.length > MAX_PLIST_DIAGNOSTIC_STRING
        ? `${node.stringValue.slice(0, MAX_PLIST_DIAGNOSTIC_STRING)}...`
        : node.stringValue;
      return JSON.stringify(truncated);
    }
    case 'array': {
      const items: string[] = [];
      const count = Math.min(node.arrayValue.length, MAX_PLIST_DIAGNOSTIC_ITEMS);
      for (let index = 0; index < count; index++) {
        items.push(formatPlistNodeDiagnostic(node.arrayValue[index], '', depth + 1));
      }
      if (count < node.arrayValue.length) {
        items.push(`... ${node.arrayValue.length - count} more`);
      }
      return `[${items.join(', ')}]`;
    }
    case 'dictionary': {
      const entries: string[] = [];
      let count = 0;
      for (const entryKey of node.dictionaryValue.keys()) {
        if (count >= MAX_PLIST_DIAGNOSTIC_ITEMS) {
          entries.push(`... ${node.dictionaryValue.size - count} more`);
          break;
        }
        const value = node.dictionaryValue.get(entryKey);
        if (!value) {
          continue;
        }
        entries.push(`${JSON.stringify(entryKey)}: ${formatPlistNodeDiagnostic(value, entryKey, depth + 1)}`);
        count++;
      }
      return `{${entries.join(', ')}}`;
    }
    default:
      return `<${node.kind}>`;
  }
}
