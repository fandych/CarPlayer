import nativeMedia from 'libmediabytes.so';

interface NativeMediaBytes {
  swapPcmS16(source: Uint8Array): Uint8Array;
}

const nativeCodec = nativeMedia as NativeMediaBytes;

export function swapPcmS16(source: Uint8Array): Uint8Array {
  return nativeCodec.swapPcmS16(source);
}