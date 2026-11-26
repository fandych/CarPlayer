// WifiLinkedInfo.ipAddress stores the first octet in the most significant byte.
export function formatWifiIpv4Address(ipAddress: number): string {
  return [
    (ipAddress >>> 24) & 0xff,
    (ipAddress >>> 16) & 0xff,
    (ipAddress >>> 8) & 0xff,
    ipAddress & 0xff
  ].join('.');
}
