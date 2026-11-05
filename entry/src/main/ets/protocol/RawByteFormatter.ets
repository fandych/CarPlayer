export const MAX_RAW_DIAGNOSTIC_BYTES: number = 16 * 1024;

export function formatRawByteBlock(
  direction: string,
  transport: string,
  bytes: Uint8Array,
  maximumBytes: number = MAX_RAW_DIAGNOSTIC_BYTES,
  maskedBytes?: Uint8Array
): string {
  const displayLength = Math.min(bytes.length, Math.max(0, maximumBytes));
  const lines: string[] = [];
  let maskedCount = 0;
  for (let offset = 0; offset < displayLength; offset += 16) {
    const rowEnd = Math.min(offset + 16, displayLength);
    const values: string[] = [];
    for (let index = offset; index < rowEnd; index++) {
      if (maskedBytes?.[index] === 1) {
        maskedCount++;
        values.push('**');
      } else {
        values.push((bytes[index] ?? 0).toString(16).padStart(2, '0'));
      }
    }
    lines.push(`${offset.toString(16).padStart(4, '0')}: ${values.join(' ')}`);
  }
  const masked = maskedCount > 0 ? `; sensitive-bytes-masked=${maskedCount}` : '';
  const omitted = bytes.length - displayLength;
  const truncated = omitted > 0 ? `; ${omitted} bytes omitted` : '';
  if (omitted > 0) {
    lines.push(`... ${omitted} bytes omitted`);
  }
  return `RAW ${direction} ${transport} bytes=${bytes.length}${masked}${truncated}` +
    (lines.length > 0 ? `\n${lines.join('\n')}` : '');
}
