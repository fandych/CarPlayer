export function isIpv6LinkLocal(address: string): boolean {
  return /^fe[89ab][0-9a-f]:/i.test(address);
}

export function ipv4AddressesSharePrefix(left: string, right: string, prefixLength: number): boolean {
  if (!Number.isInteger(prefixLength) || prefixLength < 0 || prefixLength > 32 ||
    !isIpv4Address(left) || !isIpv4Address(right)) {
    return false;
  }
  if (prefixLength === 0) {
    return true;
  }
  const blockSize = 2 ** (32 - prefixLength);
  return Math.floor(ipv4AddressNumber(left) / blockSize) === Math.floor(ipv4AddressNumber(right) / blockSize);
}

function ipv4AddressNumber(address: string): number {
  return address.split('.').reduce((value: number, octet: string): number => value * 256 + Number(octet), 0);
}

export function ipv6AddressesSharePrefix(left: string, right: string, prefixLength: number): boolean {
  if (!Number.isInteger(prefixLength) || prefixLength < 0 || prefixLength > 128) {
    return false;
  }
  const leftBytes = parseIpv6Address(left);
  const rightBytes = parseIpv6Address(right);
  if (!leftBytes || !rightBytes) {
    return false;
  }
  const fullBytes = Math.floor(prefixLength / 8);
  for (let index = 0; index < fullBytes; index++) {
    if (leftBytes[index] !== rightBytes[index]) {
      return false;
    }
  }
  const remainingBits = prefixLength % 8;
  if (remainingBits === 0) {
    return true;
  }
  const mask = (0xff << (8 - remainingBits)) & 0xff;
  return (leftBytes[fullBytes] & mask) === (rightBytes[fullBytes] & mask);
}

export function parseIpv6Address(address: string): number[] | undefined {
  const normalized = stripIpv6ScopeId(address.toLowerCase());
  if (!normalized.includes(':')) {
    return undefined;
  }
  const compressionIndex = normalized.indexOf('::');
  let groups: string[];
  if (compressionIndex >= 0) {
    if (normalized.indexOf('::', compressionIndex + 2) >= 0) {
      return undefined;
    }
    const left = normalized.slice(0, compressionIndex).split(':').filter(Boolean);
    const right = normalized.slice(compressionIndex + 2).split(':').filter(Boolean);
    const zeroCount = 8 - left.length - right.length;
    if (zeroCount < 1) {
      return undefined;
    }
    groups = left.concat(new Array<string>(zeroCount).fill('0'), right);
  } else {
    groups = normalized.split(':');
  }
  if (groups.length !== 8 || groups.some((group: string): boolean => !/^[0-9a-f]{1,4}$/.test(group))) {
    return undefined;
  }
  const bytes: number[] = [];
  for (const group of groups) {
    const value = Number.parseInt(group, 16);
    bytes.push((value >> 8) & 0xff, value & 0xff);
  }
  return bytes;
}

export function getSocketAddressFamily(address: string): number {
  return address.includes(':') ? 2 : 1;
}

export function stripIpv6ScopeId(address: string): string {
  const scopeSeparator = address.indexOf('%');
  return scopeSeparator === -1 ? address : address.slice(0, scopeSeparator);
}

export function orderAirPlayAddresses(addresses: string[]): string[] {
  const ipv4: string[] = [];
  const ipv6: string[] = [];
  const linkLocalIpv6: string[] = [];
  const other: string[] = [];
  const seen: Set<string> = new Set<string>();
  for (const address of addresses) {
    const candidate = address.trim().replace(/^\[|\]$/g, '');
    const unscopedAddress = stripIpv6ScopeId(candidate);
    if (!unscopedAddress || seen.has(unscopedAddress.toLowerCase())) {
      continue;
    }
    seen.add(unscopedAddress.toLowerCase());
    if (isIpv4Address(unscopedAddress)) {
      ipv4.push(candidate);
    } else if (unscopedAddress.includes(':') && /^fe[89ab][0-9a-f]:/i.test(unscopedAddress)) {
      linkLocalIpv6.push(candidate);
    } else if (unscopedAddress.includes(':')) {
      ipv6.push(candidate);
    } else {
      other.push(candidate);
    }
  }
  return ipv4.concat(ipv6, linkLocalIpv6, other);
}

export function isIpv4Address(address: string): boolean {
  const octets = address.split('.');
  return octets.length === 4 && octets.every((octet: string): boolean =>
    /^\d{1,3}$/.test(octet) && Number(octet) <= 255
  );
}
