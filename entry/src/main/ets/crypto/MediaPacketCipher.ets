import taskpool from '@ohos.taskpool';
import { chacha20poly1305 } from '@noble/ciphers/chacha.js';
import { chachaSeal } from './AirPlayStreamCrypto';

@Concurrent
function encryptVideoPacket(
  key: Uint8Array, nonce: Uint8Array, plaintext: Uint8Array, associatedData: Uint8Array
): Uint8Array {
  if (key.length !== 32 || nonce.length !== 12) {
    throw new Error('Invalid video AEAD key or nonce length');
  }
  return chacha20poly1305(key, nonce, associatedData).encrypt(plaintext);
}

export class MediaPacketCipher {
  private readonly key: Uint8Array;
  private readonly background: boolean;
  private readonly log: (message: string) => void;
  private completed: number = 0;

  constructor(key: Uint8Array, background: boolean = false,
    log: (message: string) => void = (_message: string): void => {}) {
    this.key = key.slice();
    this.background = background;
    this.log = log;
  }

  async seal(nonce: Uint8Array, plaintext: Uint8Array, associatedData: Uint8Array): Promise<Uint8Array> {
    if (this.background) {
      try {
        const startedAt = Date.now();
        const task = new taskpool.Task(encryptVideoPacket, this.key, nonce, plaintext, associatedData);
        task.setTransferList([]);
        const encrypted = await taskpool.execute(task, taskpool.Priority.MEDIUM) as Uint8Array;
        if (!(encrypted instanceof Uint8Array) || encrypted.length !== plaintext.length + 16) {
          throw new Error('Invalid background video encryption result');
        }
        this.completed++;
        if (this.completed === 1 || this.completed % 120 === 0) {
          this.log(`AirPlay background media encryption ready: packets=${this.completed}, ` +
            `bytes=${plaintext.length}, elapsedMs=${Date.now() - startedAt}`);
        }
        return encrypted;
      } catch (error) {
        throw new Error(
          `AirPlay background media encryption failed: ${error instanceof Error ? error.message : String(error)}`
        );
      }
    }
    return chachaSeal(this.key, nonce, plaintext, associatedData);
  }
}