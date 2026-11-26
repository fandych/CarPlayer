import { BinaryPlistDecoder } from './BinaryPlistDecoder';
import { BinaryPlistEncoder } from './BinaryPlistEncoder';
import { PlistNode } from './PlistNode';
import { formatPlistDiagnostic } from './BinaryPlistDiagnostics';
export { PlistNode, formatPlistDiagnostic };

export class BinaryPlist {
  static decode(bytes: Uint8Array): PlistNode {
    return BinaryPlistDecoder.decode(bytes);
  }

  static encode(root: PlistNode): Uint8Array {
    return BinaryPlistEncoder.encode(root);
  }
}
