const { assert, test, loadEts } = require('../ProjectionBehaviorSupport.cjs');

test('a late WLAN unregister cannot clear a replacement network registration', async () => {
  let finishOldUnregister;
  const unregistered = [];
  let connectionCount = 0;
  const handle = { netId: 3 };
  const { WifiNetworkLease } = loadEts('network/WifiNetworkLease.ets', {
    '@ohos.net.connection': {
      NetBearType: { BEARER_WIFI: 1 },
      async getAllNets() { return [handle]; },
      async getNetCapabilities() { return { bearerTypes: [1] }; },
      async getConnectionProperties() { return {
        interfaceName: 'wlan0',
        linkAddresses: [{ address: { address: '10.36.232.67' }, prefixLength: 24 }]
      }; },
      createNetConnection() {
        const id = ++connectionCount;
        return {
          on() {},
          register(callback) { callback(); },
          unregister(callback) {
            unregistered.push(id);
            if (id === 1) finishOldUnregister = callback;
            else callback();
          }
        };
      }
    }
  });
  const lease = new WifiNetworkLease();
  await lease.acquire('vehicle', () => {}, () => {}, '10.36.232.67');
  const releasing = lease.release();
  assert.equal(typeof finishOldUnregister, 'function');
  await lease.acquire('vehicle', () => {}, () => {}, '10.36.232.67');
  finishOldUnregister();
  await releasing;
  await lease.release();
  assert.deepEqual(unregistered, [1, 2]);
});
