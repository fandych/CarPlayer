function createAudioSenderFixture(loadEts) {
  const sent = [];
  const encrypted = [];
  const socket = { async bind() {}, async close() {}, async send(options) { sent.push(options); } };
  const codec = {
    concatBytes(...parts) {
      const result = new Uint8Array(parts.reduce((total, part) => total + part.length, 0));
      let offset = 0;
      for (const part of parts) { result.set(part, offset); offset += part.length; }
      return result;
    },
    toArrayBuffer(data) { return data.slice().buffer; }
  };
  const { AudioRtpSender } = loadEts('audio/AudioRtpSender.ets', {
    '../network/SocketDeadline': loadEts('network/SocketDeadline.ets'),
    '@ohos.net.socket': { constructUDPSocketInstance: () => socket },
    '../crypto/MediaPacketCipher': {
      MediaPacketCipher: class {
      async seal(nonce, data, aad) {
        encrypted.push({ nonce: nonce.slice(), data: data.slice(), aad: aad.slice() });
        return codec.concatBytes(data, new Uint8Array(16));
      }
      }
    },
    '../network/WifiNetworkLease': {
      getSocketAddressFamily: () => 1,
      WifiNetworkLease: class {}
    },
    '../protocol/Iap2Codec': codec,
    '../session/ProtocolLogger': { formatProtocolEvent: () => '' },
    './AudioRtpPacketFormat': loadEts('audio/AudioRtpPacketFormat.ets'),
    './AudioPcm': { swapPcmS16(data) {
      const result = data.slice();
      for (let offset = 0; offset < result.length; offset += 2) {
        result[offset] = data[offset + 1]; result[offset + 1] = data[offset];
      }
      return result;
    } }
  });
  const sender = new AudioRtpSender(() => {}, message => { throw new Error(message); });
  const session = { host: '127.0.0.1', dataPort: 7001, controlPort: 0,
    streamKey: new Uint8Array(32), sampleRate: 48000 };
  return { sender, session, sent, encrypted };
}

module.exports = { createAudioSenderFixture };
