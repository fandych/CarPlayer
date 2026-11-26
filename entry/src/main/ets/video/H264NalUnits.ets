export function splitH264NalUnits(data: Uint8Array): Uint8Array[] {
  if (data.length === 0) {
    return [];
  }
  const annexB = splitAnnexB(data);
  if (annexB.length > 0) {
    return annexB;
  }
  const configuration = splitConfiguration(data);
  if (configuration.length > 0) {
    return configuration;
  }
  const lengthPrefixed = splitLengthPrefixed(data);
  return lengthPrefixed.length > 0 ? lengthPrefixed : [data];
}

function splitAnnexB(data: Uint8Array): Uint8Array[] {
  const units: Uint8Array[] = [];
  let index = 0;
  let bodyStart = 0;
  let found = false;
  while (data.length - index > 3) {
    let prefixLength = 0;
    if (data[index] === 0 && data[index + 1] === 0) {
      if (data[index + 2] === 1) {
        prefixLength = 3;
      } else if (data[index + 2] === 0 && data[index + 3] === 1) {
        prefixLength = 4;
      }
    }
    if (prefixLength === 0) {
      index++;
      continue;
    }
    if (found && index > bodyStart) {
      units.push(data.subarray(bodyStart, index));
    }
    found = true;
    bodyStart = index + prefixLength;
    index = bodyStart;
  }
  if (found && data.length > bodyStart) {
    units.push(data.subarray(bodyStart));
  }
  return units;
}

function splitConfiguration(data: Uint8Array): Uint8Array[] {
  if (data.length < 7 || data[0] !== 1) {
    return [];
  }
  const units: Uint8Array[] = [];
  let offset = 6;
  for (let group = 0; group < 2; group++) {
    if (group === 1 && offset >= data.length) {
      return [];
    }
    const count = group === 0 ? data[5] & 0x1f : data[offset++];
    for (let index = 0; index < count; index++) {
      if (data.length - offset < 2) {
        return [];
      }
      const length = (data[offset] << 8) | data[offset + 1];
      offset += 2;
      if (length === 0 || length > data.length - offset) {
        return [];
      }
      units.push(data.subarray(offset, offset + length));
      offset += length;
    }
  }
  return offset === data.length ? units : [];
}

function splitLengthPrefixed(data: Uint8Array): Uint8Array[] {
  const units: Uint8Array[] = [];
  let offset = 0;
  while (data.length - offset >= 4) {
    const length = data[offset] * 0x1000000 + (data[offset + 1] << 16) +
      (data[offset + 2] << 8) + data[offset + 3];
    offset += 4;
    if (length === 0 || length > data.length - offset) {
      return [];
    }
    units.push(data.subarray(offset, offset + length));
    offset += length;
  }
  return offset === data.length ? units : [];
}