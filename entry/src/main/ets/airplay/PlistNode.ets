export class PlistNode {
  readonly kind: string;
  boolValue: boolean = false;
  integerValue: bigint = BigInt(0);
  realValue: number = 0;
  dataValue: Uint8Array = new Uint8Array(0);
  stringValue: string = '';
  arrayValue: PlistNode[] = [];
  dictionaryValue: Map<string, PlistNode> = new Map<string, PlistNode>();

  private constructor(kind: string) {
    this.kind = kind;
  }

  static nullValue(): PlistNode {
    return new PlistNode('null');
  }

  static boolean(value: boolean): PlistNode {
    const node = new PlistNode('boolean');
    node.boolValue = value;
    return node;
  }

  static integer(value: bigint | number): PlistNode {
    const node = new PlistNode('integer');
    node.integerValue = typeof value === 'number' ? BigInt(Math.trunc(value)) : value;
    return node;
  }

  static real(value: number): PlistNode {
    const node = new PlistNode('real');
    node.realValue = value;
    return node;
  }

  static data(value: Uint8Array): PlistNode {
    const node = new PlistNode('data');
    node.dataValue = value.slice();
    return node;
  }

  static string(value: string): PlistNode {
    const node = new PlistNode('string');
    node.stringValue = value;
    return node;
  }

  static array(value: PlistNode[]): PlistNode {
    const node = new PlistNode('array');
    node.arrayValue = value.slice();
    return node;
  }

  static dictionary(value: Map<string, PlistNode>): PlistNode {
    const node = new PlistNode('dictionary');
    node.dictionaryValue = new Map<string, PlistNode>(value);
    return node;
  }

  get(key: string): PlistNode | undefined {
    if (this.kind !== 'dictionary') {
      throw new Error('Property lookup requires a binary plist dictionary');
    }
    return this.dictionaryValue.get(key);
  }
}
