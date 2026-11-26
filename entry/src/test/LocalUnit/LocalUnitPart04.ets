import { it, expect } from '@ohos/hypium';
import { encodeIap2LinkFrame, encodeIap2Control, encodeIap2Parameter, encodeIap2SyncPayload, Iap2LinkDecoder, Iap2LinkFrame, concatBytes } from '../main/ets/protocol/Iap2Codec';
import { Iap2SenderSession, shouldProbeLegacyWifi } from '../main/ets/session/Iap2SenderSession';

export default function LocalUnitPart04(): void {
  it('reuses the data sequence for ACK-only frames and rejects EAK as CSM', 0, async (): Promise<void> => {
        const sent: Uint8Array[] = [];
        const session = new Iap2SenderSession(
          async (bytes: Uint8Array): Promise<void> => { sent.push(bytes.slice()); },
          (): void => {},
          (): void => {},
          (): void => {},
          '34:86:DA:86:BB:96',
          'test-device',
          'test-uuid'
        );
        const decoder = new Iap2LinkDecoder();
        let sentOffset = 0;
        const decodeNewOutput = (): Iap2LinkFrame[] => {
          const frames: Iap2LinkFrame[] = [];
          while (sentOffset < sent.length) {
            frames.push(...decoder.push(sent[sentOffset]));
            sentOffset++;
          }
          return frames;
        };
  
        await session.start();
        decodeNewOutput();
        await session.receive(encodeIap2LinkFrame({
          control: 0x80,
          sequence: 169,
          acknowledgement: 0,
          sessionId: 0,
          payload: encodeIap2SyncPayload(1)
        }));
        const negotiationOutput = decodeNewOutput();
        const identificationStart = negotiationOutput.find((frame: Iap2LinkFrame) =>
          frame.payload.length >= 6 && frame.payload[4] === 0x1d && frame.payload[5] === 0x00
        );
        expect(identificationStart !== undefined).assertTrue();
  
        const identityBody = concatBytes(
          encodeIap2Parameter(6, new Uint8Array([0xaa, 0x06])),
          encodeIap2Parameter(7, new Uint8Array([0x43, 0x00]))
        );
        await session.receive(encodeIap2LinkFrame({
          control: 0x40,
          sequence: 170,
          acknowledgement: identificationStart?.sequence ?? 0,
          sessionId: 1,
          payload: encodeIap2Control(0x1d01, identityBody)
        }));
        const identityOutput = decodeNewOutput();
        const linkAcknowledgement = identityOutput.find((frame: Iap2LinkFrame) =>
          frame.control === 0x40 && frame.payload.length === 0
        );
        const certificateRequest = identityOutput.find((frame: Iap2LinkFrame) =>
          frame.payload.length >= 6 && frame.payload[4] === 0xaa && frame.payload[5] === 0x00
        );
        expect(linkAcknowledgement?.sequence).assertEqual(identificationStart?.sequence);
        expect(session.isAuthenticationComplete).assertFalse();
        expect(certificateRequest !== undefined).assertTrue();
        expect(identityOutput.some((frame: Iap2LinkFrame) =>
          frame.payload.length >= 6 && frame.payload[4] === 0xaa && frame.payload[5] === 0x05
        )).assertFalse();
  
        await session.receive(encodeIap2LinkFrame({
          control: 0x40,
          sequence: 170,
          acknowledgement: identificationStart?.sequence ?? 0,
          sessionId: 1,
          payload: encodeIap2Control(0x1d01, identityBody)
        }));
        const duplicateOutput = decodeNewOutput();
        expect(duplicateOutput.length).assertEqual(1);
        expect(duplicateOutput[0].payload.length).assertEqual(0);
        expect(duplicateOutput[0].acknowledgement).assertEqual(170);
  
        const outputCount = sent.length;
        await session.receive(encodeIap2LinkFrame({
          control: 0x60,
          sequence: 171,
          acknowledgement: identificationStart?.sequence ?? 0,
          sessionId: 0,
          payload: new Uint8Array([certificateRequest?.sequence ?? 0])
        }));
        expect(sent.length).assertEqual(outputCount + 1);
        const retransmissions = decodeNewOutput();
        expect(retransmissions.length).assertEqual(1);
        expect(retransmissions[0].sequence).assertEqual(certificateRequest?.sequence);
        expect(retransmissions[0].payload[4]).assertEqual(0xaa);
        expect(retransmissions[0].payload[5]).assertEqual(0x00);
        session.cancel();
      });
  
  it('requests missing iAP2 frames and delivers buffered data in sequence', 0, async (): Promise<void> => {
        const sent: Uint8Array[] = [];
        const session = new Iap2SenderSession(
          async (bytes: Uint8Array): Promise<void> => { sent.push(bytes.slice()); },
          (): void => {}, (): void => {}, (): void => {},
          '34:86:DA:86:BB:96', 'test-device', 'test-uuid'
        );
        const decoder = new Iap2LinkDecoder();
        await session.start();
        await session.receive(encodeIap2LinkFrame({
          control: 0x80, sequence: 254, acknowledgement: 0, sessionId: 0,
          payload: encodeIap2SyncPayload(1)
        }));
        sent.length = 0;
        const identity = encodeIap2Control(0x1d01, new Uint8Array(0));
        await session.receive(encodeIap2LinkFrame({
          control: 0x40, sequence: 0, acknowledgement: 0, sessionId: 1,
          payload: identity.slice(3)
        }));
        let output = sent.flatMap((bytes: Uint8Array): Iap2LinkFrame[] => decoder.push(bytes));
        expect(output.length).assertEqual(1);
        expect(output[0].control).assertEqual(0x60);
        expect(output[0].acknowledgement).assertEqual(254);
        expect(output[0].payload[0]).assertEqual(255);
        sent.length = 0;
        await session.receive(encodeIap2LinkFrame({
          control: 0x40, sequence: 255, acknowledgement: 0, sessionId: 1,
          payload: identity.slice(0, 3)
        }));
        output = sent.flatMap((bytes: Uint8Array): Iap2LinkFrame[] => decoder.push(bytes));
        expect(output.some((frame: Iap2LinkFrame): boolean =>
          frame.payload.length >= 6 && frame.payload[4] === 0xaa && frame.payload[5] === 0x00
        )).assertTrue();
        session.cancel();
      });
  
  it('reports malformed MFi certificates to the accessory as AA04', 0, async (): Promise<void> => {
        const sent: Uint8Array[] = [];
        const session = new Iap2SenderSession(
          async (bytes: Uint8Array): Promise<void> => { sent.push(bytes.slice()); },
          (): void => {}, (): void => {}, (): void => {},
          '34:86:DA:86:BB:96', 'test-device', 'test-uuid'
        );
        await session.start();
        await session.receive(encodeIap2LinkFrame({
          control: 0x80, sequence: 10, acknowledgement: 0, sessionId: 0, payload: encodeIap2SyncPayload(1)
        }));
        sent.length = 0;
        await session.receive(encodeIap2LinkFrame({
          control: 0x40, sequence: 11, acknowledgement: 0, sessionId: 1,
          payload: encodeIap2Control(0xaa01, new Uint8Array(0))
        }));
        const decoder = new Iap2LinkDecoder();
        const frames: Iap2LinkFrame[] = [];
        for (const bytes of sent) {
          frames.push(...decoder.push(bytes));
        }
        expect(frames.some((frame: Iap2LinkFrame): boolean =>
          frame.payload.length >= 6 && frame.payload[4] === 0xaa && frame.payload[5] === 0x04
        )).assertTrue();
        expect(session.isAuthenticationComplete).assertFalse();
        session.cancel();
      });
  
  it('terminates iAP2 on reset and ignores subsequent data', 0, async (): Promise<void> => {
        const sent: Uint8Array[] = [];
        const session = new Iap2SenderSession(
          async (bytes: Uint8Array): Promise<void> => { sent.push(bytes.slice()); },
          (): void => {}, (): void => {}, (): void => {},
          '34:86:DA:86:BB:96', 'test-device', 'test-uuid'
        );
        await session.start();
        let resetReported = false;
        try {
          await session.receive(encodeIap2LinkFrame({
            control: 0x10, sequence: 0, acknowledgement: 0, sessionId: 0, payload: new Uint8Array(0)
          }));
        } catch (_error) {
          resetReported = true;
        }
        expect(resetReported).assertTrue();
        expect(session.isAuthenticationComplete).assertFalse();
        const outputCount = sent.length;
        await session.receive(encodeIap2LinkFrame({
          control: 0x80, sequence: 1, acknowledgement: 0, sessionId: 0, payload: encodeIap2SyncPayload(1)
        }));
        expect(sent.length).assertEqual(outputCount);
      });
  
  it('probes legacy Wi-Fi for unknown or sparse accessory capabilities', 0, () => {
        expect(shouldProbeLegacyWifi(undefined, undefined)).assertTrue();
        expect(shouldProbeLegacyWifi([0x4301, 0x6800], [0x4300, 0x4e09, 0x4e0a, 0x4e0b, 0x4e0c]))
          .assertTrue();
        expect(shouldProbeLegacyWifi([], [])).assertTrue();
        expect(shouldProbeLegacyWifi([1, 2, 3, 4, 5], [6, 7, 8, 9, 10])).assertFalse();
        expect(shouldProbeLegacyWifi(Array(10).fill(0x4301), undefined)).assertFalse();
        expect(shouldProbeLegacyWifi([0x5703], [])).assertTrue();
      });
}
