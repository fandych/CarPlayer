import nativeProjection from 'libprojection.so';

interface NativeProjectionCapabilities {
  isVideoEncoderSizeSupported(width: number, height: number): boolean;
}

const nativeApi = nativeProjection as NativeProjectionCapabilities;

export function isH264EncoderSizeSupported(width: number, height: number): boolean {
  return nativeApi.isVideoEncoderSizeSupported(width, height);
}
