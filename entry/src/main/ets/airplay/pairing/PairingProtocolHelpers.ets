import { encodeUtf8 } from '../../protocol/Iap2Codec';
import { Tlv8Type } from '../Tlv8';

interface PairSetupErrorDetails {
  code?: number | string;
  message?: string;
  name?: string;
}

export async function withPairSetupStage<T>(stage: string, operation: () => Promise<T>): Promise<T> {
  try {
    return await operation();
  } catch (error) {
    const details = error as PairSetupErrorDetails;
    const parts: string[] = [];
    if (details.name) {
      parts.push(details.name);
    }
    if (details.code !== undefined) {
      parts.push(`code=${details.code}`);
    }
    if (details.message) {
      parts.push(details.message);
    }
    const message = parts.length > 0 ? parts.join(': ') : String(error);
    throw new Error(`${stage} failed: ${message}`);
  }
}

export function required(values: Map<number, Uint8Array>, type: number, field: string): Uint8Array {
  const value = values.get(type);
  if (!value) {
    throw new Error(`Missing ${field}`);
  }
  return value;
}

export function requireState(values: Map<number, Uint8Array>, expected: number, field: string): void {
  const state = values.get(Tlv8Type.STATE);
  if (!state || state.length !== 1 || state[0] !== expected) {
    const error = values.get(Tlv8Type.ERROR);
    const errorCode = error && error.length > 0 ? error[0].toString() : 'unknown';
    throw new Error(`${field} returned unexpected state; error=${errorCode}`);
  }
}

export function nonceLabel(label: string): Uint8Array {
  const nonce = new Uint8Array(12);
  const bytes = encodeUtf8(label);
  nonce.set(bytes.slice(0, 8), 4);
  return nonce;
}

export function constantTimeEqual(left: Uint8Array, right: Uint8Array): boolean {
  if (left.length !== right.length) {
    return false;
  }
  let difference = 0;
  for (let index = 0; index < left.length; index++) {
    difference |= left[index] ^ right[index];
  }
  return difference === 0;
}
