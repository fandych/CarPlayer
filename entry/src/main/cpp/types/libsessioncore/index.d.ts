declare module 'libsessioncore.so' {
  export function advanceGeneration(): string;
  export function isCurrentGeneration(generation: string): boolean;
}
