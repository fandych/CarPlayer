import { it, expect } from '@ohos/hypium';
import { encodeIap2Control, encodeIap2Parameter, encodeUtf8, formatIap2LinkPayloadDiagnostic, concatBytes } from '../main/ets/protocol/Iap2Codec';
import { parseMfiCertificatePayload, readMessageIds } from '../main/ets/session/Iap2SenderSession';
import { isMfiPinEligiblePkixFailure, MfiVerifier, verifyRawMfiP256Signature } from '../main/ets/iap2/MfiVerifier';
import { appendConnectionLog, MAX_CONNECTION_LOG_LINES } from '../main/ets/session/ConnectionLogBuffer';
import { formatProtocolEvent, ProtocolLogger } from '../main/ets/session/ProtocolLogger';
import { formatLocalClock, formatLocalDateKey, formatLocalTimestamp } from '../main/ets/session/LogTimestamp';
import { BinaryPlist, PlistNode } from '../main/ets/airplay/BinaryPlist';
import { patchH264SpsLevel } from '../main/ets/airplay/AirPlayVideoStream';

export default function LocalUnitPart05(): void {
  it('verifies raw P-256 MFi signatures without hashing the challenge again', 0, () => {
        const fromHex = (hex: string): Uint8Array => {
          const bytes = new Uint8Array(hex.length / 2);
          for (let index = 0; index < bytes.length; index++) {
            bytes[index] = parseInt(hex.slice(index * 2, index * 2 + 2), 16);
          }
          return bytes;
        };
        const publicKey = fromHex(
          '3059301306072a8648ce3d020106082a8648ce3d03010703420004' +
          '8e533b6fa0bf7b4625bb30667c01fb607ef9f8b8a80fef5b300628703187b2a3' +
          '73eb1dbde03318366d069f83a6f5900053c73633cb041b21c55e1a86c1f400b4'
        );
        const signature = fromHex(
          'b2415773cc980676059a7b930cc8ff2f29bdee8de7f5379f3ea3ad4ea3f0435f' +
          'aa1fb2c6830f9e5009a093366b93220b76da3e580a2d2e6a1faa0e46592f1a9f'
        );
        const alternate = fromHex(
          'b2415773cc980676059a7b930cc8ff2f29bdee8de7f5379f3ea3ad4ea3f0435f' +
          '55e04d387cf061b0f65f6cc9946cddf4460cbc559cea701ad40fbc7ca3340ab2'
        );
        const challenge = new Uint8Array(32).fill(42);
        expect(verifyRawMfiP256Signature(publicKey, challenge, signature)).assertTrue();
        expect(verifyRawMfiP256Signature(publicKey, challenge, alternate)).assertTrue();
        challenge[0] ^= 1;
        expect(verifyRawMfiP256Signature(publicKey, challenge, signature)).assertFalse();
        challenge[0] ^= 1;
        signature[0] ^= 1;
        expect(verifyRawMfiP256Signature(publicKey, challenge, signature)).assertFalse();
        expect(verifyRawMfiP256Signature(publicKey.slice(0, 20), challenge, alternate)).assertFalse();
      });
  
  it('continues after an unverified challenge only in explicit diagnostic mode', 0, () => {
        const strictVerifier = new MfiVerifier((): void => {});
        const diagnosticVerifier = new MfiVerifier((): void => {}, false, [], undefined, undefined, true);
        expect(strictVerifier.canContinueAfterChallengeVerification(false)).assertFalse();
        expect(strictVerifier.canContinueAfterChallengeVerification(true)).assertTrue();
        expect(diagnosticVerifier.canContinueAfterChallengeVerification(false)).assertTrue();
        expect(diagnosticVerifier.canContinueAfterChallengeVerification(true)).assertTrue();
      });
  
  it('allows MFi fingerprint pinning only for certificate-chain trust failures', 0, () => {
        expect(isMfiPinEligiblePkixFailure('unable to get local issuer certificate')).assertTrue();
        expect(isMfiPinEligiblePkixFailure('untrusted certificate')).assertTrue();
        expect(isMfiPinEligiblePkixFailure('key cannot be used for a digital signature')).assertFalse();
        expect(isMfiPinEligiblePkixFailure('unsupported critical extension')).assertFalse();
        expect(isMfiPinEligiblePkixFailure('19030005')).assertFalse();
      });
  
  it('keeps protocol log history bounded and chronological', 0, () => {
        let lines: string[] = [];
        for (let index = 0; index < MAX_CONNECTION_LOG_LINES + 2; index++) {
          lines = appendConnectionLog(lines, `line-${index}`);
        }
        expect(lines.length).assertEqual(MAX_CONNECTION_LOG_LINES);
        expect(lines[0]).assertEqual('line-2');
        expect(lines[lines.length - 1]).assertEqual(`line-${MAX_CONNECTION_LOG_LINES + 1}`);
      });
  
  it('adds structured metadata and redacts protocol secrets', 0, () => {
        let line = '';
        const logger = new ProtocolLogger((entry: string): void => {
          line = entry;
        });
        logger.write('wifi', 'password=example-secret privateKey: hidden-key', 'WARN');
        expect(line.startsWith('[')).assertTrue();
        expect(line.includes('] WARN wifi:')).assertTrue();
        expect(line.includes('#')).assertFalse();
        expect(line.includes('[REDACTED]')).assertTrue();
        expect(line.includes('example-secret')).assertFalse();
        expect(line.includes('hidden-key')).assertFalse();
      });
  
  it('formats log timestamps in the device local timezone', 0, () => {
        const date = new Date(2026, 9, 27, 12, 34, 56, 789);
        const timestamp = formatLocalTimestamp(date);
        const offsetMinutes = -date.getTimezoneOffset();
        const offsetSign = offsetMinutes >= 0 ? '+' : '-';
        const offsetMagnitude = Math.abs(offsetMinutes);
        const expectedOffset = `${offsetSign}${Math.floor(offsetMagnitude / 60).toString().padStart(2, '0')}:` +
          `${(offsetMagnitude % 60).toString().padStart(2, '0')}`;
        expect(timestamp.startsWith('2026-10-27T12:34:56.789')).assertTrue();
        expect(timestamp.endsWith(expectedOffset)).assertTrue();
        expect(timestamp.endsWith('Z')).assertFalse();
        expect(formatLocalDateKey(date)).assertEqual('2026-10-27');
        expect(formatLocalClock(date)).assertEqual('[12:34:56.789]');
      });
  
  it('formats JSON protocol events and redacts sensitive field names and assignments', 0, () => {
        const event = formatProtocolEvent('wifi.connect',
          'ssid', 'DIRECT-example',
          'securityType', 2,
          'passphrase', 'must-not-appear',
          'detail', 'challenge=private-challenge'
        );
        expect(event.includes('"event":"wifi.connect"')).assertTrue();
        expect(event.includes('"ssid":"DIRECT-example"')).assertTrue();
        expect(event.includes('[REDACTED]')).assertTrue();
        expect(event.includes('must-not-appear')).assertFalse();
        expect(event.includes('private-challenge')).assertFalse();
      });
  
  it('logs full ordinary link payloads and redacts sensitive CSM payloads', 0, () => {
        const ordinaryBody = new Uint8Array(300).fill(0x5a);
        const ordinary = formatIap2LinkPayloadDiagnostic('RX', encodeIap2Control(0x1d01, ordinaryBody));
        expect(ordinary.includes('body=300B hex=')).assertTrue();
        expect(ordinary.includes('bytes omitted')).assertFalse();
  
        const signature = new Uint8Array([0xde, 0xad, 0xbe, 0xef]);
        const mfi = formatIap2LinkPayloadDiagnostic('RX', encodeIap2Control(
          0xaa03,
          encodeIap2Parameter(0, signature)
        ));
        expect(mfi.includes('[REDACTED:MFi]')).assertTrue();
        expect(mfi.includes('de ad be ef')).assertFalse();
  
        const password = encodeUtf8('private-wifi-password');
        const wifi = formatIap2LinkPayloadDiagnostic('RX', encodeIap2Control(
          0x5703,
          encodeIap2Parameter(2, password)
        ));
        expect(wifi.includes('[REDACTED:Wi-Fi password]')).assertTrue();
        expect(wifi.includes('private-wifi-password')).assertFalse();
      });
  
  it('keeps absent or malformed iAP2 capability lists unknown', 0, () => {
        expect(readMessageIds(undefined)).assertUndefined();
        expect(readMessageIds(new Uint8Array([0x43]))).assertUndefined();
        const ids = readMessageIds(new Uint8Array([0x43, 0x00, 0x57, 0x02]));
        expect(ids?.length).assertEqual(2);
        expect(ids?.[0]).assertEqual(0x4300);
        expect(ids?.[1]).assertEqual(0x5702);
      });
  
  it('combines the xcertplay BAA leaf and intermediate certificate parameters', 0, () => {
        const leaf = new Uint8Array([0x30, 0x03, 0x02, 0x01, 0x01]);
        const intermediate = new Uint8Array([0x30, 0x03, 0x02, 0x01, 0x02]);
        const body = concatBytes(
          encodeIap2Parameter(0, leaf),
          encodeIap2Parameter(1, new Uint8Array([1])),
          encodeIap2Parameter(2, intermediate)
        );
        const parsed = parseMfiCertificatePayload(body);
        expect(parsed.length).assertEqual(leaf.length + intermediate.length);
        expect(parsed[0]).assertEqual(leaf[0]);
        expect(parsed[leaf.length]).assertEqual(intermediate[0]);
      });
  
  it('decodes compact unsigned plist integers and preserves signed 64-bit values', 0, () => {
        const fixtures: Uint8Array[] = [
          new Uint8Array([0x10, 0xff]),
          new Uint8Array([0x11, 0xc3, 0x50]),
          new Uint8Array([0x12, 0x80, 0x00, 0x00, 0x00])
        ];
        const expected: bigint[] = [BigInt(255), BigInt(50000), BigInt('2147483648')];
        for (let index = 0; index < fixtures.length; index++) {
          const fixture = fixtures[index];
          const bytes = new Uint8Array(8 + fixture.length + 1 + 32);
          bytes.set(encodeUtf8('bplist00'), 0);
          bytes.set(fixture, 8);
          bytes[8 + fixture.length] = 8;
          const trailer = bytes.length - 32;
          bytes[trailer + 6] = 1;
          bytes[trailer + 7] = 1;
          bytes[trailer + 15] = 1;
          bytes[trailer + 31] = 8 + fixture.length;
          expect(BinaryPlist.decode(bytes).integerValue.toString()).assertEqual(expected[index].toString());
        }
        const negative = BinaryPlist.encode(PlistNode.integer(-1));
        expect(negative[8]).assertEqual(0x13);
        expect(BinaryPlist.decode(negative).integerValue.toString()).assertEqual('-1');
      });
  
  it('raises low H.264 SPS level to 4.0 without lowering higher levels', 0, () => {
        const lowLevelSps = new Uint8Array([0x67, 0x64, 0x00, 0x1f, 0x80]);
        const highLevelSps = new Uint8Array([0x67, 0x64, 0x00, 0x2a, 0x80]);
        expect(patchH264SpsLevel(lowLevelSps)[3]).assertEqual(0x28);
        expect(lowLevelSps[3]).assertEqual(0x1f);
        expect(patchH264SpsLevel(highLevelSps)).assertEqual(highLevelSps);
      });
}
