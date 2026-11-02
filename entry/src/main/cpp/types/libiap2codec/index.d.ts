declare module 'libiap2codec.so' {
  export interface Tlv8DecodeResult {
    ranges: Uint32Array;
    values: Uint8Array;
  }

  export function encodeLink(
    control: number, sequence: number, acknowledgement: number, session: number, payload: Uint8Array
  ): Uint8Array;
  export function scanLink(bytes: Uint8Array): number[];
  export function encodeControl(messageId: number, body: Uint8Array): Uint8Array;
  export function encodeParameter(id: number, value: Uint8Array): Uint8Array;
  export function scanControl(bytes: Uint8Array): number[];
  export function parseParameters(bytes: Uint8Array): number[];
  export function encodeTlv8(types: Uint8Array, values: Uint8Array[]): Uint8Array;
  export function decodeTlv8(bytes: Uint8Array): Tlv8DecodeResult;
}