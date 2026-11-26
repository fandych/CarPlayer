function createEtsLoader({ assert, fs, path, vm, ts, sourceRoot }) {
  function loadEts(relativePath, imports = {}, selectFunction) {
    const filename = path.join(sourceRoot, relativePath);
    if (relativePath === 'session/iap2/Iap2LinkLayer.ets') {
      imports = {
        ...imports,
        './Iap2LinkLayerReceive': loadEts('session/iap2/Iap2LinkLayerReceive.ets', imports)
      };
    }
    if (relativePath === 'airplay/AirPlayVideoStream.ets') {
      const packets = loadEts('airplay/AirPlayVideoPackets.ets', {
        '../video/H264NalUnits': imports['../video/H264NalUnits'] || {}
      });
      imports = {
        ...imports,
        './AirPlayVideoPackets': packets,
        './AirPlayVideoLegacyCipher': loadEts('airplay/AirPlayVideoLegacyCipher.ets', {
          '@ohos.security.cryptoFramework': imports['@ohos.security.cryptoFramework'] || {}
        }),
        './AirPlayVideoFrameQueue': loadEts('airplay/AirPlayVideoFrameQueue.ets', {
          './AirPlayVideoPackets': packets
        })
      };
    }
    if (relativePath === 'pages/ProjectionAppCatalog.ets') {
      imports = {
        ...imports,
        './ProjectionAppTypes': {},
        './ProjectionAppCatalogData': loadEts('pages/ProjectionAppCatalogData.ets', {
          './ProjectionAppTypes': {}
        })
      };
    }
    if (relativePath === 'video/ProjectionSettings.ets') {
      imports = {
        ...imports,
        './ProjectionSettingsTypes': loadEts('video/ProjectionSettingsTypes.ets'),
        './ProjectionSplitSettings': loadEts('video/ProjectionSplitSettings.ets', {
          './ProjectionSettingsTypes': loadEts('video/ProjectionSettingsTypes.ets')
        })
      };
    }
    if (relativePath === 'airplay/pairing/PairingProtocol.ets') {
      imports = {
        ...imports,
        './PairingProtocolHelpers': loadEts('airplay/pairing/PairingProtocolHelpers.ets', {
          '../../protocol/Iap2Codec': imports['../../protocol/Iap2Codec'] || {},
          '../Tlv8': imports['../Tlv8'] || {}
        })
      };
    }
    if (relativePath === 'transport/BluetoothIap2Server.ets') {
      imports = {
        ...imports,
        './BluetoothIap2AcceptRetry': loadEts('transport/BluetoothIap2AcceptRetry.ets')
      };
    }
    if (relativePath === 'network/WifiNetworkLease.ets') {
      const addresses = loadEts('network/WifiNetworkAddress.ets');
      imports = {
        ...imports,
        './WifiNetworkAddress': addresses,
        './WifiNetworkErrors': loadEts('network/WifiNetworkErrors.ets'),
        './WifiNetworkAddressResolver': loadEts('network/WifiNetworkAddressResolver.ets', {
          '@ohos.net.connection': imports['@ohos.net.connection'] || {},
          './WifiNetworkAddress': addresses
        })
      };
    }
    if (relativePath === 'airplay/BinaryPlist.ets') {
      const plistNode = loadEts('airplay/PlistNode.ets');
      imports = {
        ...imports,
        './PlistNode': plistNode,
        './BinaryPlistDecoder': loadEts('airplay/BinaryPlistDecoder.ets', {
          '@ohos.util': imports['@ohos.util'] || {},
          '../protocol/Iap2Codec': imports['../protocol/Iap2Codec'] || {},
          './PlistNode': plistNode
        }),
        './BinaryPlistEncoder': loadEts('airplay/BinaryPlistEncoder.ets', {
          '../protocol/Iap2Codec': imports['../protocol/Iap2Codec'] || {},
          './PlistNode': plistNode
        }),
        './BinaryPlistDiagnostics': loadEts('airplay/BinaryPlistDiagnostics.ets', {
          './PlistNode': plistNode
        })
      };
    }
    let source = fs.readFileSync(filename, 'utf8');
    if (selectFunction) {
      const parsed = ts.createSourceFile(filename, source, ts.ScriptTarget.Latest, true);
      const declaration = parsed.statements.find(statement =>
        ts.isFunctionDeclaration(statement) && statement.name?.text === selectFunction);
      assert.ok(declaration, `Missing function ${selectFunction}`);
      source = `${declaration.getText(parsed)}\nexports.${selectFunction} = ${selectFunction};`;
    }
    const result = ts.transpileModule(source, {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
    });
    const exports = {};
    const requireMock = name => {
      assert.ok(Object.hasOwn(imports, name), `Unexpected import ${name}`);
      return { __esModule: true, default: imports[name], ...imports[name] };
    };
    const execute = vm.runInThisContext(`(function(exports, require) { ${result.outputText}\n})`, { filename });
    execute(exports, requireMock);
    return exports;
  }
  return loadEts;
}

module.exports = { createEtsLoader };
