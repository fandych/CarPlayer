import cryptoFramework from '@ohos.security.cryptoFramework';
import { concatBytes, encodeUtf8 } from '../protocol/Iap2Codec';

export interface AirPlayAsymmetricKeyPair {
  privateKeyDer: Uint8Array;
  publicKeyRaw: Uint8Array;
}

export async function sha512(...parts: Uint8Array[]): Promise<Uint8Array> {
  const digest = cryptoFramework.createMd('SHA512');
  for (const part of parts) {
    const input: cryptoFramework.DataBlob = { data: part };
    await digest.update(input);
  }
  return (await digest.digest()).data;
}

export async function hkdfSha512(
  inputKey: Uint8Array,
  salt: Uint8Array,
  info: Uint8Array,
  length: number = 32
): Promise<Uint8Array> {
  if (length < 1 || length > 64 * 255) {
    throw new Error('HKDF output length is out of range');
  }
  const effectiveSalt = salt.length > 0 ? salt : new Uint8Array(64);
  const pseudorandomKey = await hmacSha512(effectiveSalt, inputKey);
  let output = new Uint8Array(0);
  let previousBlock = new Uint8Array(0);
  let counter = 1;
  while (output.length < length) {
    previousBlock = await hmacSha512(
      pseudorandomKey,
      concatBytes(previousBlock, info, new Uint8Array([counter]))
    );
    output = concatBytes(output, previousBlock);
    counter++;
  }
  return output.slice(0, length);
}

async function hmacSha512(keyBytes: Uint8Array, data: Uint8Array): Promise<Uint8Array> {
  const blockSize = 128;
  const key = keyBytes.length > blockSize ? await sha512(keyBytes) : keyBytes;
  const innerPad = new Uint8Array(blockSize);
  const outerPad = new Uint8Array(blockSize);
  for (let index = 0; index < blockSize; index++) {
    const keyByte = index < key.length ? key[index] : 0;
    innerPad[index] = keyByte ^ 0x36;
    outerPad[index] = keyByte ^ 0x5c;
  }
  return sha512(outerPad, await sha512(innerPad, data));
}

export async function generateEd25519KeyPair(): Promise<AirPlayAsymmetricKeyPair> {
  const generator = cryptoFramework.createAsyKeyGenerator('Ed25519');
  const pair = await generator.generateKeyPair();
  return {
    privateKeyDer: pair.priKey.getEncoded().data,
    publicKeyRaw: pair.pubKey.getEncoded().data.slice(-32)
  };
}

export async function signEd25519(privateKeyDer: Uint8Array, data: Uint8Array): Promise<Uint8Array> {
  const generator = cryptoFramework.createAsyKeyGenerator('Ed25519');
  const privateKeyBlob: cryptoFramework.DataBlob = { data: privateKeyDer };
  const pair = await generator.convertKey(null, privateKeyBlob);
  const signer = cryptoFramework.createSign('Ed25519');
  await signer.init(pair.priKey);
  const payload: cryptoFramework.DataBlob = { data };
  return (await signer.sign(payload)).data;
}

export async function verifyEd25519(
  publicKeyRaw: Uint8Array,
  data: Uint8Array,
  signature: Uint8Array
): Promise<boolean> {
  if (publicKeyRaw.length !== 32 || signature.length !== 64) {
    return false;
  }
  const publicKeyDer = concatBytes(
    new Uint8Array([0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x03, 0x21, 0x00]),
    publicKeyRaw
  );
  const generator = cryptoFramework.createAsyKeyGenerator('Ed25519');
  const publicKeyBlob: cryptoFramework.DataBlob = { data: publicKeyDer };
  const pair = await generator.convertKey(publicKeyBlob, null);
  const verifier = cryptoFramework.createVerify('Ed25519');
  await verifier.init(pair.pubKey);
  const payload: cryptoFramework.DataBlob = { data };
  const signatureBlob: cryptoFramework.DataBlob = { data: signature };
  return verifier.verify(payload, signatureBlob);
}

export async function generateX25519KeyPair(): Promise<AirPlayAsymmetricKeyPair> {
  const generator = cryptoFramework.createAsyKeyGenerator('X25519');
  const pair = await generator.generateKeyPair();
  return {
    privateKeyDer: pair.priKey.getEncoded().data,
    publicKeyRaw: pair.pubKey.getEncoded().data.slice(-32)
  };
}

export async function x25519SharedSecret(
  privateKeyDer: Uint8Array,
  peerPublicKeyRaw: Uint8Array
): Promise<Uint8Array> {
  if (peerPublicKeyRaw.length !== 32) {
    throw new Error('X25519 peer public key must be exactly 32 bytes');
  }
  const publicKeyDer = concatBytes(
    new Uint8Array([0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x6e, 0x03, 0x21, 0x00]),
    peerPublicKeyRaw
  );
  const generator = cryptoFramework.createAsyKeyGenerator('X25519');
  const privateKeyBlob: cryptoFramework.DataBlob = { data: privateKeyDer };
  const publicKeyBlob: cryptoFramework.DataBlob = { data: publicKeyDer };
  const localPair = await generator.convertKey(null, privateKeyBlob);
  const peerPair = await generator.convertKey(publicKeyBlob, null);
  const agreement = cryptoFramework.createKeyAgreement('X25519');
  return (await agreement.generateSecret(localPair.priKey, peerPair.pubKey)).data;
}

export function nonce64(counter: number): Uint8Array {
  const nonce = new Uint8Array(12);
  let remaining = counter;
  for (let index = 4; index < 12; index++) {
    nonce[index] = remaining & 0xff;
    remaining = Math.floor(remaining / 256);
  }
  return nonce;
}

export function nonceLabel(label: string): Uint8Array {
  const bytes = new Uint8Array(12);
  const encoded = encodeUtf8(label);
  bytes.set(encoded.slice(0, 8), 4);
  return bytes;
}
