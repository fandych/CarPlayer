import { chacha20poly1305 } from '@noble/ciphers/chacha.js';
import type { CipherWithOutput } from '@noble/ciphers/utils.js';

export async function chachaSeal(
  keyBytes: Uint8Array,
  nonce: Uint8Array,
  plaintext: Uint8Array,
  associatedData: Uint8Array
): Promise<Uint8Array> {
  if (keyBytes.length !== 32 || nonce.length !== 12) {
    throw new Error('ChaCha20-Poly1305 requires a 32-byte key and 12-byte nonce');
  }
  const cipher: CipherWithOutput = associatedData.length > 0
    ? chacha20poly1305(keyBytes, nonce, associatedData)
    : chacha20poly1305(keyBytes, nonce);
  return cipher.encrypt(plaintext);
}

export async function chachaOpen(
  keyBytes: Uint8Array,
  nonce: Uint8Array,
  ciphertextAndTag: Uint8Array,
  associatedData: Uint8Array
): Promise<Uint8Array> {
  if (keyBytes.length !== 32 || nonce.length !== 12) {
    throw new Error('ChaCha20-Poly1305 requires a 32-byte key and 12-byte nonce');
  }
  const cipher: CipherWithOutput = associatedData.length > 0
    ? chacha20poly1305(keyBytes, nonce, associatedData)
    : chacha20poly1305(keyBytes, nonce);
  return cipher.decrypt(ciphertextAndTag);
}
