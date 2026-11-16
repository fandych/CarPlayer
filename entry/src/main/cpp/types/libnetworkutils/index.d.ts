declare module 'libnetworkutils.so' {
  export function setIpv6SocketInterface(socketFd: number, interfaceName: string): void;
}
