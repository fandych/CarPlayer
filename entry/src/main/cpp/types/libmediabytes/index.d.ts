declare module 'libmediabytes.so' {
  export function swapPcmS16(source: Uint8Array): Uint8Array;
  export function splitH264(source: Uint8Array): Uint32Array;
}