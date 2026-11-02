export type AirPlayIdentityRelation = 'public-key-match' | 'identifier-match' | 'conflict' | 'different-device' | 'unlinked';

export function correlateAirPlayIdentity(
  mdnsIdentifier: string,
  mdnsPublicKey: string,
  endpointIdentifier: string,
  endpointPublicKey: string
): AirPlayIdentityRelation {
  const normalizedMdnsKey = normalizePublicKey(mdnsPublicKey);
  const normalizedEndpointKey = normalizePublicKey(endpointPublicKey);
  const normalizedMdnsIdentifier = normalizeDeviceIdentifier(mdnsIdentifier);
  const normalizedEndpointIdentifier = normalizeDeviceIdentifier(endpointIdentifier);
  const identifiersMatch = normalizedMdnsIdentifier.length > 0 &&
    normalizedMdnsIdentifier === normalizedEndpointIdentifier;
  const hasPublicKeys = normalizedMdnsKey.length > 0 && normalizedEndpointKey.length > 0;

  if (hasPublicKeys) {
    if (normalizedMdnsKey === normalizedEndpointKey) {
      return 'public-key-match';
    }
    return identifiersMatch ? 'conflict' : 'different-device';
  }
  if (normalizedMdnsIdentifier.length > 0 && normalizedEndpointIdentifier.length > 0) {
    return identifiersMatch ? 'identifier-match' : 'different-device';
  }
  return 'unlinked';
}

function normalizePublicKey(value: string): string {
  const normalized = value.startsWith('0x') ? value.slice(2) : value;
  return /^[0-9a-fA-F]{64}$/.test(normalized) ? normalized.toLowerCase() : '';
}

function normalizeDeviceIdentifier(value: string): string {
  return value.trim().replace(/[:-]/g, '').toLowerCase();
}