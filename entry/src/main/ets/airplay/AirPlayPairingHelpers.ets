const HK_PAIRING_AND_ENCRYPT: bigint = BigInt('0x4000000000');

export function supportsAirPlayPairingAndEncryption(features: string | undefined): boolean | undefined {
  if (!features) {
    return undefined;
  }
  const words = features.split(',');
  if (words.length !== 2) {
    return undefined;
  }
  const parseWord = (word: string): bigint | undefined => {
    const normalized = word.trim().replace(/^0x/i, '');
    if (!/^[0-9a-f]{1,8}$/i.test(normalized)) {
      return undefined;
    }
    return BigInt(`0x${normalized}`);
  };
  const low = parseWord(words[0]);
  const high = parseWord(words[1]);
  if (low === undefined || high === undefined) {
    return undefined;
  }
  const combined = (high << BigInt(32)) | low;
  return (combined & HK_PAIRING_AND_ENCRYPT) !== BigInt(0);
}

export function decodeAirPlayHex(hex: string): Uint8Array {
  const normalized = hex.startsWith('0x') ? hex.slice(2) : hex;
  if (normalized.length % 2 !== 0 || !/^[0-9a-fA-F]*$/.test(normalized)) {
    throw new Error('AirPlay TXT public key is not valid hexadecimal');
  }
  const result = new Uint8Array(normalized.length / 2);
  for (let index = 0; index < result.length; index++) {
    result[index] = parseInt(normalized.slice(index * 2, index * 2 + 2), 16);
  }
  return result;
}

export function equalAirPlayBytes(left: Uint8Array, right: Uint8Array): boolean {
  if (left.length !== right.length) {
    return false;
  }
  let difference = 0;
  for (let index = 0; index < left.length; index++) {
    difference |= left[index] ^ right[index];
  }
  return difference === 0;
}
