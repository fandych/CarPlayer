import { describe, it, expect } from '@ohos/hypium';
import {
  concatBytes, decodeIap2Parameters, encodeIap2Control, encodeIap2LinkFrame, encodeIap2Parameter,
  Iap2ControlDecoder, Iap2LinkDecoder, Iap2LinkFrame
} from '../../../main/ets/protocol/Iap2Codec';
import { decodeTlv8, encodeTlv8 } from '../../../main/ets/airplay/Tlv8';
import { advanceSessionGeneration, isCurrentSessionGeneration } from '../../../main/ets/session/NativeSessionLifecycle';
import { swapPcmS16 } from '../../../main/ets/audio/AudioPcm';
import { splitH264NalUnits } from '../../../main/ets/video/NativeH264Data';

export default function nativeIap2CodecTest(): void {
  describe('NativeIap2Codec', (): void => {
    it('encodes a typed array subview with the expected byte order', 0, (): void => {
      const backing = new Uint8Array([0xee, 0x12, 0x34, 0xee]);
      const value = backing.subarray(1, 3);
      const parameter = encodeIap2Parameter(0xabcd, value);
      const message = encodeIap2Control(0xaa01, parameter);
      expect(Array.from(message).join(',')).assertEqual('64,64,0,12,170,1,0,6,171,205,18,52');
      const parsed = decodeIap2Parameters(parameter);
      expect(parsed.length).assertEqual(1);
      expect(parsed[0].id).assertEqual(0xabcd);
      expect(Array.from(parsed[0].value).join(',')).assertEqual('18,52');
    });

    it('recovers after a corrupted link frame and assembles split control frames', 0, (): void => {
      const message = encodeIap2Control(0xaa01, new Uint8Array([0x12, 0x34]));
      const frame: Iap2LinkFrame = {
        control: 0x40, sequence: 11, acknowledgement: 0, sessionId: 1, payload: message
      };
      const valid = encodeIap2LinkFrame(frame);
      const corrupted = valid.slice();
      corrupted[9] ^= 1;
      const decoder = new Iap2LinkDecoder();
      const input = concatBytes(new Uint8Array([1, 2]), corrupted, valid);
      expect(decoder.push(input.slice(0, input.length - 1)).length).assertEqual(0);
      const decoded = decoder.push(input.slice(input.length - 1));
      expect(decoded.length).assertEqual(1);
      expect(decoded[0].sequence).assertEqual(11);
      const control = new Iap2ControlDecoder();
      expect(control.push(decoded[0].payload.slice(0, 3)).length).assertEqual(0);
      const messages = control.push(decoded[0].payload.slice(3));
      expect(messages.length).assertEqual(1);
      expect(messages[0].messageId).assertEqual(0xaa01);
      expect(Array.from(messages[0].body).join(',')).assertEqual('18,52');
    });

    it('rejects truncated or oversized parameters', 0, (): void => {
      let malformedRejected = false;
      let oversizedRejected = false;
      try {
        decodeIap2Parameters(new Uint8Array([0, 6, 0, 1, 0x12]));
      } catch (_error) {
        malformedRejected = true;
      }
      try {
        encodeIap2Parameter(1, new Uint8Array(65532));
      } catch (_error) {
        oversizedRejected = true;
      }
      expect(malformedRejected).assertTrue();
      expect(oversizedRejected).assertTrue();
    });

    it('encodes TLV8 fragments natively and reassembles continuation values', 0, (): void => {
      const source = new Uint8Array(258);
      for (let index = 0; index < source.length; index++) source[index] = index & 0xff;
      const encoded = encodeTlv8([{ type: 3, value: source.subarray(1, 257) }]);
      expect(encoded[0]).assertEqual(3);
      expect(encoded[1]).assertEqual(255);
      expect(encoded[257]).assertEqual(3);
      expect(encoded[258]).assertEqual(1);
      const decoded = decodeTlv8(encoded);
      expect(decoded.get(3)?.length).assertEqual(256);
      expect(decoded.get(3)?.[0]).assertEqual(1);
      expect(decoded.get(3)?.[255]).assertEqual(0);

      const repeated = encodeTlv8([
        { type: 4, value: new Uint8Array([0x11]) },
        { type: 4, value: new Uint8Array([0x22]) }
      ]);
      expect(Array.from(repeated).join(',')).assertEqual('4,1,17,255,0,4,1,34');
      expect(decodeTlv8(repeated).get(4)?.[0]).assertEqual(0x22);
    });

    it('invalidates stale lifecycle tokens in the native session core', 0, (): void => {
      const first = advanceSessionGeneration();
      expect(isCurrentSessionGeneration(first)).assertTrue();
      const second = advanceSessionGeneration();
      expect(first === second).assertFalse();
      expect(isCurrentSessionGeneration(first)).assertFalse();
      expect(isCurrentSessionGeneration(second)).assertTrue();
    });

    it('converts PCM subviews without changing their backing buffer', 0, (): void => {
      const input = new Uint8Array([0xee, 0x34, 0x12, 0xfe, 0xff, 0xee]);
      const converted = swapPcmS16(input.subarray(1, 5));
      expect(Array.from(converted).join(',')).assertEqual('18,52,255,254');
      expect(Array.from(input).join(',')).assertEqual('238,52,18,254,255,238');
      let oddRejected = false;
      try {
        swapPcmS16(input.subarray(0, 3));
      } catch (_error) {
        oddRejected = true;
      }
      expect(oddRejected).assertTrue();
    });

    it('splits H.264 NAL units from a typed array subview', 0, (): void => {
      const backing = new Uint8Array([0xee, 0, 0, 0, 1, 0x67, 1, 0, 0, 1, 0x68, 2, 0xee]);
      const units = splitH264NalUnits(backing.subarray(1, backing.length - 1));
      expect(units.length).assertEqual(2);
      expect(Array.from(units[0]).join(',')).assertEqual('103,1');
      expect(Array.from(units[1]).join(',')).assertEqual('104,2');
      expect(splitH264NalUnits(new Uint8Array(0)).length).assertEqual(0);
    });
  });
}