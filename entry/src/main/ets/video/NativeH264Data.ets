import nativeMedia from 'libmediabytes.so';

interface NativeH264Data {
  splitH264(source: Uint8Array): Uint32Array;
}

const nativeCodec = nativeMedia as NativeH264Data;

export function splitH264NalUnits(data: Uint8Array): Uint8Array[] {
  const pairs = nativeCodec.splitH264(data);
  const units: Uint8Array[] = [];
  for (let index = 0; index < pairs.length; index += 2) {
    units.push(data.subarray(pairs[index], pairs[index] + pairs[index + 1]));
  }
  return units;
}