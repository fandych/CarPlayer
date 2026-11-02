import nativeSessionCore from 'libsessioncore.so';

export function advanceSessionGeneration(): string {
  return nativeSessionCore.advanceGeneration();
}

export function isCurrentSessionGeneration(generation: string): boolean {
  return nativeSessionCore.isCurrentGeneration(generation);
}
