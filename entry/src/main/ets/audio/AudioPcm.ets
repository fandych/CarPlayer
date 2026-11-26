export function swapPcmS16(source: Uint8Array): Uint8Array {
  if ((source.length & 1) !== 0) {
    throw new Error('PCM S16 data must contain complete 16-bit samples');
  }
  const converted = new Uint8Array(source.length);
  for (let offset = 0; offset < source.length; offset += 2) {
    converted[offset] = source[offset + 1];
    converted[offset + 1] = source[offset];
  }
  return converted;
}