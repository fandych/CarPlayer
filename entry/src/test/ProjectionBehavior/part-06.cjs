const { assert, fs, path, vm, test, ts, sourceRoot, audioSenderFixture, loadEts, loadMethods,
  loadProjectionSettingsController, videoSenderFixture } = require('../ProjectionBehaviorSupport.cjs');

test('AirPlay SETUP payloads include et=NONE and the virtual iAP2 command shape', () => {
  const concatBytes = (...parts) => {
    const result = new Uint8Array(parts.reduce((length, part) => length + part.length, 0));
    let offset = 0;
    for (const part of parts) {
      result.set(part, offset);
      offset += part.length;
    }
    return result;
  };
  const util = {
    TextDecoder: { create: () => ({ decodeToString: bytes => new TextDecoder().decode(bytes) }) }
  };
  const { BinaryPlist, PlistNode } = loadEts('airplay/BinaryPlist.ets', {
    '@ohos.util': util,
    '../protocol/Iap2Codec': { concatBytes, encodeUtf8: text => new TextEncoder().encode(text) }
  });
  const audioSetup = loadMethods('airplay/media/AirPlayMediaSessionPayloads.ets', 'AirPlayMediaSessionPayloads',
    ['buildAudioSetupPayload'], { BinaryPlist, PlistNode, SAMPLES_PER_PACKET: 352 });
  const audio = BinaryPlist.decode(audioSetup.buildAudioSetupPayload(123n, 1n << 15n, 250));
  const streams = audio.get('streams');
  assert.equal(streams.kind, 'array');
  assert.equal(streams.arrayValue.length, 1);
  assert.equal(Number(streams.arrayValue[0].get('framesPerPacket').integerValue), 352);
  assert.equal(Number(streams.arrayValue[0].get('spf').integerValue), 352);
  const hidModeSetup = loadMethods('airplay/media/AirPlayMediaSessionPayloads.ets', 'AirPlayMediaSessionPayloads',
    ['buildHidSetInputModePayload'], { BinaryPlist, PlistNode });
  const hidMode = BinaryPlist.decode(hidModeSetup.buildHidSetInputModePayload('2A2A2A2A'));
  assert.equal(hidMode.get('type').stringValue, 'hidSetInputMode');
  assert.equal(Number(hidMode.get('params').get('hidInputMode').integerValue), 0);
  assert.equal(hidMode.get('params').get('uuid').stringValue, '2a2a2a2a');
  const mediaSessionSource = fs.readFileSync(
    path.join(sourceRoot, 'airplay/media/AirPlayMediaSessionStart.ets'), 'utf8');
  const eventSetupSource = fs.readFileSync(
    path.join(sourceRoot, 'airplay/media/AirPlayMediaSessionStartHelpers.ets'), 'utf8');
  assert.ok(mediaSessionSource.indexOf("'video stream SETUP'") <
    mediaSessionSource.indexOf('await this.setupEventChannel(eventPort, sharedSecret'));
  assert.ok(eventSetupSource.indexOf('await eventChannel.connect(this.receiverHost, eventPort, sharedSecret)') <
    eventSetupSource.indexOf('eventChannel.sendCommand(AirPlayMediaSessionPayloads.buildHidSetInputModePayload'));

  const sessionSource = fs.readFileSync(
    path.join(sourceRoot, 'airplay/media/AirPlayMediaSessionPayloads.ets'), 'utf8');
  const featureBlock = /const CONTROLLER_FEATURES:\s*string\[\]\s*=\s*\[([\s\S]*?)\];/.exec(sessionSource);
  assert.ok(featureBlock);
  const controllerFeatures = Array.from(featureBlock[1].matchAll(/'([^']+)'/g), match => match[1]);
  const expectedFeatures = [
    'uiContext', 'viewAreas', 'cornerMasks', 'focusTransfer', 'h.264Level5.1', 'mainBuffered',
    'altScreen', 'enhancedSiri', 'hevc', 'sessionManagement', 'logTransfer', 'iAPChannel',
    'vehicleStateProtocol', 'videoPlayback'
  ];
  assert.deepEqual(controllerFeatures, expectedFeatures);
  const sessionSetup = loadMethods('airplay/media/AirPlayMediaSessionPayloads.ets', 'AirPlayMediaSessionPayloads',
    ['buildSessionSetupPayload', 'buildIapSendMessagePayload'], {
      BinaryPlist,
      PlistNode,
      CONTROLLER_FEATURES: controllerFeatures,
      CARPLAY_SENDER_MAC_ADDRESS: 'aa:bb:cc:dd:ee:ff',
      CARPLAY_SENDER_OS_BUILD_VERSION: 'test-build',
      CARPLAY_SENDER_SOURCE_VERSION: 'test-version',
      createUuid: () => 'test-uuid',
      normalizeDeviceId: value => value
    });
  const session = BinaryPlist.decode(sessionSetup.buildSessionSetupPayload('AA:BB:CC:DD:EE:FF', 7000));
  assert.equal(session.get('features').kind, 'array');
  assert.deepEqual(session.get('features').arrayValue.map(feature => feature.stringValue), expectedFeatures);
  assert.equal(session.get('deviceID').stringValue, 'AA:BB:CC:DD:EE:FF');
  assert.equal(session.get('macAddress').stringValue, 'aa:bb:cc:dd:ee:ff');
  assert.equal(session.get('name').stringValue, 'iPhone');
  assert.equal(session.get('model').stringValue, 'iPhone14,2');
  assert.equal(session.get('osName').stringValue, 'iPhone OS');
  assert.equal(session.get('osVersion').stringValue, '15.0.2');
  assert.equal(session.get('osBuildVersion').stringValue, 'test-build');
  assert.equal(session.get('sessionUUID').stringValue, 'TEST-UUID');
  assert.equal(session.get('sessionCorrelationUUID').stringValue, 'TEST-UUID');
  assert.equal(session.get('timingPort').integerValue, 7000n);
  const legacySession = BinaryPlist.decode(
    sessionSetup.buildSessionSetupPayload('AA:BB:CC:DD:EE:FF', 7000, true)
  );
  assert.equal(legacySession.get('et').integerValue, 1n);
  assert.equal(session.get('et'), undefined);
  const marker = new Uint8Array([0xff, 0x55, 0x02, 0x00, 0xee, 0x10]);
  const iapCommand = BinaryPlist.decode(sessionSetup.buildIapSendMessagePayload(marker));
  assert.equal(iapCommand.get('type').stringValue, 'iAPSendMessage');
  assert.deepEqual(iapCommand.get('params').get('data').dataValue, marker);

  const screenSetupAt = mediaSessionSource.indexOf("'video stream SETUP'");
  const mib3DetectAt = mediaSessionSource.indexOf('buildIapSendMessagePayload(MIB3_IAP2_DETECT_MARKER)');
  const eventChannelAt = mediaSessionSource.indexOf('await this.setupEventChannel(eventPort, sharedSecret');
  const recordAt = mediaSessionSource.indexOf("'RECORD'");
  assert.ok(screenSetupAt < mib3DetectAt && mib3DetectAt < eventChannelAt && eventChannelAt < recordAt);
});

test('MIB3 virtual iAP2 accepts event-channel bytes and reaches identification over the RTSP command route', async () => {
  const checksum = bytes => {
    let sum = 0;
    for (const byte of bytes) sum = (sum + byte) & 0xff;
    return (-sum) & 0xff;
  };
  const encodeLink = (control, sequence, acknowledgement, session, payload) => {
    const length = 9 + payload.length + (payload.length > 0 ? 1 : 0);
    const frame = new Uint8Array(length);
    frame.set([0xff, 0x5a, length >>> 8, length & 0xff, control, sequence,
      acknowledgement, session]);
    frame[8] = checksum(frame.slice(0, 8));
    frame.set(payload, 9);
    if (payload.length > 0) frame[length - 1] = checksum(payload);
    return frame;
  };
  const scanLink = bytes => {
    for (let offset = 0; offset + 9 <= bytes.length; offset++) {
      if (bytes[offset] !== 0xff || bytes[offset + 1] !== 0x5a) continue;
      const length = (bytes[offset + 2] << 8) | bytes[offset + 3];
      if (length < 9 || offset + length > bytes.length) return [offset, 0, 0];
      if (checksum(bytes.slice(offset, offset + 9)) !== 0 ||
        checksum(bytes.slice(offset + 9, offset + length)) !== 0) continue;
      return [offset + length, offset, length];
    }
    return [Math.max(0, bytes.length - 1), 0, 0];
  };
  const encodeControl = (messageId, body) => {
    const result = new Uint8Array(6 + body.length);
    result.set([0x40, 0x40, result.length >>> 8, result.length & 0xff,
      messageId >>> 8, messageId & 0xff]);
    result.set(body, 6);
    return result;
  };
  const codec = {
    encodeIap2LinkFrame: frame => encodeLink(frame.control, frame.sequence,
      frame.acknowledgement, frame.sessionId, frame.payload),
    encodeIap2Control: encodeControl,
    formatIap2RawFrameDiagnostic: () => '',
    formatIap2LinkPayloadDiagnostic: () => '',
    formatIap2MessageDiagnostic: () => '',
    concatBytes: (...parts) => {
      const result = new Uint8Array(parts.reduce((size, part) => size + part.length, 0));
      let offset = 0;
      for (const part of parts) { result.set(part, offset); offset += part.length; }
      return result;
    },
    Iap2LinkDecoder: class {
      buffer = new Uint8Array(0);
      push(chunk, onEvent) {
        this.buffer = codec.concatBytes(this.buffer, chunk);
        const frames = [];
        while (true) {
          const [consumed, start, length] = scanLink(this.buffer);
          if (!length) {
            this.buffer = this.buffer.slice(consumed);
            break;
          }
          const raw = this.buffer.slice(start, start + length);
          const frame = {
            control: raw[4], sequence: raw[5], acknowledgement: raw[6], sessionId: raw[7],
            payload: raw.slice(9, length - 1), raw
          };
          frames.push(frame);
          this.buffer = this.buffer.slice(consumed);
          onEvent?.(frame);
        }
        return frames;
      }
    },
    Iap2ControlDecoder: class {},
    decodeIap2Parameters: () => [],
    decodeIap2String: () => '',
    numberParameter: () => new Uint8Array(0),
    stringParameter: () => new Uint8Array(0),
    groupedParameter: () => new Uint8Array(0)
  };
  const sessionProtocol = loadEts('session/iap2/Iap2SessionProtocol.ets', {
    '../../protocol/Iap2Codec': codec,
    '@ohos.i18n': { System: { getSystemLanguage: () => 'en-US' } },
    '../ProtocolLogger': { formatProtocolEvent: () => '' }
  });
  const linkLayer = loadEts('session/iap2/Iap2LinkLayer.ets', {
    '../../protocol/Iap2Codec': codec,
    './Iap2SessionProtocol': sessionProtocol
  });
  const sessionState = loadEts('session/iap2/Iap2SenderSessionState.ets', {
    '@ohos.app.ability.common': {},
    '../../protocol/Iap2Codec': codec,
    '../../iap2/MfiVerifier': { MfiVerifier: class {} },
    './Iap2SessionProtocol': sessionProtocol,
    './WirelessSessionParser': {},
    './Iap2LinkLayer': linkLayer
  });
  const sessionAuthenticationFlow = loadEts(
    'session/iap2/Iap2SenderSessionAuthenticationFlow.ets',
    {
      '@ohos.data.preferences': {},
      '@ohos.security.cryptoFramework': {},
      '../../protocol/Iap2Codec': codec,
      './Iap2SessionProtocol': sessionProtocol,
      './Iap2SenderSessionState': sessionState
    }
  );
  const sessionPostAuthenticationFlow = loadEts(
    'session/iap2/Iap2SenderSessionPostAuthenticationFlow.ets',
    {
      '../../protocol/Iap2Codec': codec,
      './Iap2SessionProtocol': sessionProtocol,
      './Iap2SenderSessionAuthenticationFlow': sessionAuthenticationFlow
    }
  );
  const sessionAnnouncements = loadEts('session/iap2/Iap2SenderSessionAnnouncements.ets', {
    '@ohos.security.cryptoFramework': {},
    '../../protocol/Iap2Codec': codec,
    './Iap2SessionProtocol': sessionProtocol,
    './Iap2SenderSessionPostAuthenticationFlow': sessionPostAuthenticationFlow
  });
  const sessionFlow = loadEts('session/iap2/Iap2SenderSessionFlow.ets', {
    './Iap2SenderSessionAnnouncements': sessionAnnouncements
  });
  const sessionMfiMessages = loadEts('session/iap2/Iap2SenderSessionMfiMessages.ets', {
    '../../protocol/Iap2Codec': codec,
    './Iap2SessionProtocol': sessionProtocol,
    './Iap2SenderSessionFlow': sessionFlow
  });
  const sessionMessages = loadEts('session/iap2/Iap2SenderSessionMessages.ets', {
    '../../protocol/Iap2Codec': codec,
    '../ProtocolLogger': { formatProtocolEvent: () => '', formatRawBytesDiagnostic: () => '' },
    './Iap2SessionProtocol': sessionProtocol,
    './WirelessSessionParser': {},
    './Iap2SenderSessionMfiMessages': sessionMfiMessages
  });
  const sessionTransport = loadEts('session/iap2/Iap2SenderSessionTransport.ets', {
    '../ProtocolLogger': { formatProtocolEvent: () => '', formatRawBytesDiagnostic: () => '' },
    '../../protocol/Iap2Codec': codec,
    './Iap2SessionProtocol': sessionProtocol,
    './Iap2SenderSessionMessages': sessionMessages
  });
  const { Iap2SenderSession } = loadEts('session/Iap2SenderSession.ets', {
    './iap2/Iap2SenderSessionTransport': sessionTransport,
    './iap2/Iap2SessionProtocol': sessionProtocol,
    './iap2/WirelessSessionParser': {}
  });
  const outbound = [];
  const sender = new Iap2SenderSession(
    async bytes => { outbound.push(bytes); }, () => {}, () => {}, () => {},
    'AA:BB:CC:DD:EE:FF', 'MIB3', 'test-uuid', false, [], undefined, undefined,
    false, undefined, () => {}, true
  );
  await sender.start(false);
  const synPayload = new Uint8Array([
    1, 4, 0x04, 0x00, 0x0f, 0xa0, 0x0f, 0xa0, 4, 4,
    10, 0, 2, 11, 2, 1, 12, 1, 2
  ]);
  const eventChannelData = encodeLink(0x80, 7, 0, 0, synPayload);
  await sender.receive(eventChannelData);
  assert.equal(outbound.length, 2);
  const syncAck = outbound.map(bytes => ({
    control: bytes[4], sequence: bytes[5], acknowledgement: bytes[6], sessionId: bytes[7],
    payload: bytes.slice(9, bytes.length - (bytes.length > 9 ? 1 : 0))
  }));
  assert.equal(syncAck[0].control, 0xc0);
  assert.equal(syncAck[0].acknowledgement, 7);
  assert.deepEqual(syncAck[0].payload, synPayload);
  assert.equal(syncAck[1].control, 0x40);
  assert.equal(syncAck[1].sessionId, 10);
  assert.deepEqual(Array.from(syncAck[1].payload.slice(4, 6)), [0x1d, 0x00]);
  sender.cancel();
  sender.cancel();

  const { parseIapSendMessagePayload } = loadEts(
    'airplay/media/AirPlayMediaHelpers.ets', {}, 'parseIapSendMessagePayload'
  );
  const incoming = {
    kind: 'dictionary',
    get(key) {
      if (key === 'type') return { kind: 'string', stringValue: 'iAPSendMessage' };
      if (key === 'params') return {
        kind: 'dictionary',
        get: name => name === 'data' ? { kind: 'data', dataValue: eventChannelData } : undefined
      };
      return undefined;
    }
  };
  assert.deepEqual(parseIapSendMessagePayload(incoming), eventChannelData);
});
