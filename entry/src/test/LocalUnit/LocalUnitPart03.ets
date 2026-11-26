import { it, expect } from '@ohos/hypium';
import { encodeIap2LinkFrame, encodeIap2SyncPayload, Iap2LinkDecoder, Iap2LinkFrame, concatBytes } from '../main/ets/protocol/Iap2Codec';
import { Iap2SenderSession } from '../main/ets/session/Iap2SenderSession';

export default function LocalUnitPart03(): void {
  it('decodes iAP2 link frames split across RFCOMM reads', 0, () => {
        const frame: Iap2LinkFrame = {
          control: 0x40,
          sequence: 12,
          acknowledgement: 9,
          sessionId: 10,
          payload: new Uint8Array([0x40, 0x40, 0x00, 0x06, 0x57, 0x03])
        };
        const encoded = encodeIap2LinkFrame(frame);
        const decoder = new Iap2LinkDecoder();
        expect(decoder.push(encoded.slice(0, 7)).length).assertEqual(0);
        const decoded = decoder.push(encoded.slice(7));
        expect(decoded.length).assertEqual(1);
        expect(decoded[0].sequence).assertEqual(frame.sequence);
        expect(decoded[0].sessionId).assertEqual(frame.sessionId);
      });
  
  it('recognizes split detection markers without treating frame payload as a marker', 0, async (): Promise<void> => {
        const sent: Uint8Array[] = [];
        const session = new Iap2SenderSession(
          async (bytes: Uint8Array): Promise<void> => { sent.push(bytes.slice()); },
          (): void => {}, (): void => {}, (): void => {},
          '34:86:DA:86:BB:96', 'test-device', 'test-uuid'
        );
        const marker = new Uint8Array([0xff, 0x55, 0x02, 0x00, 0xee, 0x10]);
        await session.start();
        sent.length = 0;
        await session.receive(marker.slice(0, 3));
        expect(sent.length).assertEqual(0);
        await session.receive(concatBytes(marker.slice(3), encodeIap2LinkFrame({
          control: 0x80, sequence: 70, acknowledgement: 0, sessionId: 0,
          payload: encodeIap2SyncPayload(1)
        })));
        expect(sent[0].length).assertEqual(marker.length);
        expect(sent[0].every((value: number, index: number): boolean => value === marker[index])).assertTrue();
        const synAck = new Iap2LinkDecoder().push(sent[1]);
        expect(synAck[0].control).assertEqual(0xc0);
        expect(synAck[0].sequence).assertEqual(99);
        expect(synAck[0].acknowledgement).assertEqual(70);
        const count = sent.length;
        await session.receive(encodeIap2LinkFrame({
          control: 0x40, sequence: 71, acknowledgement: 0, sessionId: 2, payload: marker
        }));
        expect(sent.length).assertEqual(count + 1);
        expect(sent[count].length).assertEqual(9);
        session.cancel();
      });
  
  it('does not echo repeated detection markers or change sequence for a retransmitted SYN', 0,
        async (): Promise<void> => {
          const sent: Uint8Array[] = [];
          const session = new Iap2SenderSession(
            async (bytes: Uint8Array): Promise<void> => { sent.push(bytes.slice()); },
            (): void => {}, (): void => {}, (): void => {},
            '34:86:DA:86:BB:96', 'test-device', 'test-uuid'
          );
          const marker = new Uint8Array([0xff, 0x55, 0x02, 0x00, 0xee, 0x10]);
          const sync = encodeIap2LinkFrame({
            control: 0x80, sequence: 70, acknowledgement: 0, sessionId: 0,
            payload: encodeIap2SyncPayload(1)
          });
          await session.start();
          await session.receive(marker);
          const afterMarker = sent.length;
          await session.receive(marker);
          expect(sent.length).assertEqual(afterMarker);
          await session.receive(sync);
          const decoder = new Iap2LinkDecoder();
          const initialFrames = sent.flatMap((bytes: Uint8Array): Iap2LinkFrame[] => decoder.push(bytes));
          const response = initialFrames.find((frame: Iap2LinkFrame): boolean => frame.control === 0xc0);
          const afterSync = sent.length;
          await session.receive(sync);
          expect(sent.length).assertEqual(afterSync + 1);
          const duplicate = decoder.push(sent[afterSync]);
          expect(duplicate[0].sequence).assertEqual(response?.sequence);
          session.cancel();
        });
  
  it('retries iAP2 detection and stops retries after cancellation', 0, async (): Promise<void> => {
        const sent: Uint8Array[] = [];
        const session = new Iap2SenderSession(
          async (bytes: Uint8Array): Promise<void> => { sent.push(bytes.slice()); },
          (): void => {}, (): void => {}, (): void => {},
          '34:86:DA:86:BB:96', 'test-device', 'test-uuid'
        );
        await session.start();
        const initialCount = sent.length;
        await new Promise<void>((resolve: () => void): void => { setTimeout(resolve, 1200); });
        expect(sent.length).assertEqual(initialCount + 1);
        expect(sent[initialCount].length).assertEqual(6);
        expect(new Iap2LinkDecoder().push(sent[initialCount]).length).assertEqual(0);
        session.cancel();
        const cancelledCount = sent.length;
        await new Promise<void>((resolve: () => void): void => { setTimeout(resolve, 1200); });
        expect(sent.length).assertEqual(cancelledCount);
      });
  
  it('restarts iAP2 negotiation when the accessory repeats detection', 0, async (): Promise<void> => {
        const sent: Uint8Array[] = [];
        const session = new Iap2SenderSession(
          async (bytes: Uint8Array): Promise<void> => { sent.push(bytes.slice()); },
          (): void => {}, (): void => {}, (): void => {},
          '34:86:DA:86:BB:96', 'test-device', 'test-uuid'
        );
        const marker = new Uint8Array([0xff, 0x55, 0x02, 0x00, 0xee, 0x10]);
        const sync = encodeIap2LinkFrame({
          control: 0x80, sequence: 70, acknowledgement: 0, sessionId: 0,
          payload: encodeIap2SyncPayload(1)
        });
        await session.start();
        await session.receive(sync);
        sent.length = 0;
        await session.receive(concatBytes(marker, sync));
        const decoder = new Iap2LinkDecoder();
        const frames = sent.flatMap((bytes: Uint8Array): Iap2LinkFrame[] => decoder.push(bytes));
        expect(sent[0].length).assertEqual(marker.length);
        expect(frames.some((frame: Iap2LinkFrame): boolean =>
          frame.payload.length >= 6 && frame.payload[4] === 0x1d && frame.payload[5] === 0x00)).assertTrue();
        expect(session.isAuthenticationComplete).assertFalse();
        session.cancel();
      });
  
  it('encodes and decodes pure iAP2 acknowledgements as 9-byte frames', 0, () => {
        const frame: Iap2LinkFrame = {
          control: 0x40,
          sequence: 12,
          acknowledgement: 9,
          sessionId: 0,
          payload: new Uint8Array(0)
        };
        const encoded = encodeIap2LinkFrame(frame);
        const decoded = new Iap2LinkDecoder().push(encoded);
        expect(encoded.length).assertEqual(9);
        expect(decoded.length).assertEqual(1);
        expect(decoded[0].payload.length).assertEqual(0);
        expect(decoded[0].acknowledgement).assertEqual(9);
      });
}
