function createVideoSenderFixture(loadEts, send, split = data => [data]) {
  const sent = [];
  const encrypted = [];
  const legacyCryptoCalls = [];
  let keyFrameRequests = 0;
  const concatBytes = (...parts) => {
    const result = new Uint8Array(parts.reduce((total, part) => total + part.length, 0));
    let offset = 0;
    for (const part of parts) { result.set(part, offset); offset += part.length; }
    return result;
  };
  const api = loadEts('airplay/AirPlayVideoStream.ets', {
    '@ohos.security.cryptoFramework': {
      CryptoMode: { ENCRYPT_MODE: 0 },
      createSymKeyGenerator: () => ({ async convertKey(key) { return key; } }),
      createCipher: algorithm => ({
        async init(mode, key, params) { legacyCryptoCalls.push({ algorithm, mode, key, params }); },
        async update(data) {
          legacyCryptoCalls.push({ update: data.data.slice() });
          return { data: data.data.slice() };
        },
        async doFinal(data) {
          legacyCryptoCalls.push({ doFinal: data });
          return { data: new Uint8Array(0) };
        }
      })
    },
    '../crypto/MediaPacketCipher': { MediaPacketCipher: class {
      async seal(nonce, data, aad) {
        encrypted.push({ nonce: nonce.slice(), aad: aad.slice(), data: data.slice() });
        return concatBytes(data, new Uint8Array(16));
      }
    } },
    '../protocol/Iap2Codec': { concatBytes },
    '../session/ProtocolLogger': { formatProtocolEvent: () => '' },
    '../video/H264NalUnits': { splitH264NalUnits: split }
  });
  const sender = new api.AirPlayVideoStreamSender(new Uint8Array(32), 1280, 720,
    async data => { sent.push(data); if (send) { await send(data); } },
    () => {}, () => { keyFrameRequests++; });
  const event = (type, data, flags = 0) => ({ type, data, flags, timestampUs: 0 });
  const sps = new Uint8Array([0x67, 0x64, 0, 0x1f, 0x80]);
  const pps = new Uint8Array([0x68, 0x80]);
  const frame = new Uint8Array([0x41, 0x80]);
  const configure = async () => {
    await sender.handleEncoderEvent(event('codecConfig', sps));
    await sender.handleEncoderEvent(event('codecConfig', pps));
  };
  return {
    sender,
    VideoSender: api.AirPlayVideoStreamSender,
    VideoEncryptionMode: api.AirPlayVideoEncryptionMode,
    sent,
    encrypted,
    event,
    sps,
    pps,
    frame,
    configure,
    keyFrameRequests: () => keyFrameRequests, legacyCryptoCalls };
}

module.exports = { createVideoSenderFixture };
