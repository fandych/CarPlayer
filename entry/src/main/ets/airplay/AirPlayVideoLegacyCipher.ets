import cryptoFramework from '@ohos.security.cryptoFramework';

export async function initializeLegacyVideoCipher(
  keyBytes: Uint8Array,
  ivBytes?: Uint8Array
): Promise<cryptoFramework.Cipher> {
  if (!ivBytes) {
    throw new Error('AirPlay AES-128-CTR IV is missing');
  }
  const keyGenerator = cryptoFramework.createSymKeyGenerator('AES128');
  const key = await keyGenerator.convertKey({ data: keyBytes });
  const cipher = cryptoFramework.createCipher('AES128|CTR|NoPadding');
  const params: cryptoFramework.IvParamsSpec = {
    algName: 'IvParamsSpec',
    iv: { data: ivBytes }
  };
  await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, key, params);
  return cipher;
}

export async function finishLegacyVideoCipher(cipher?: cryptoFramework.Cipher): Promise<void> {
  if (cipher) {
    await cipher.doFinal(null);
  }
}
