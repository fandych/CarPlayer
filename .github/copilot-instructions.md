# Copilot instructions

## Build, test, and lint

- This is a HarmonyOS app built with Hvigor. Build the `entry` module for the `default` product in DevEco Studio (`Build > Build Hap(s)/APP(s)`). The repository does not include an Hvigor wrapper or package-script build command.
- Run the Node host behavior tests from the repository root:
  - All tests: `node --test entry\src\test\ProjectionBehavior.test.cjs`
  - One test: `node --test --test-name-pattern="irregular-display calibration preserves aspect ratio" entry\src\test\ProjectionBehavior.test.cjs` (replace the pattern with a test title or regular expression).
  - The host test loads TypeScript from the DevEco SDK. Set `DEVECO_SDK_HOME` if the SDK is not at the script's default path.
- Run the native C tests in PowerShell from the repository root: `.\entry\src\test\native\run-tests.ps1`. Set `DEVECO_SDK_HOME` when DevEco Studio is installed outside the default location.
- Run Hypium tests with DevEco Studio's test runner. The `ohosTest` suite exercises the N-API boundary on a HarmonyOS device; building the app or test package alone does not verify device behavior. Host Hypium tests use an ArkTS stand-in and do not test native execution.
- `code-linter.json5` configures the ArkTS lint rules and exclusions. There is no checked-in lint script.

## Architecture

- The root Hvigor project builds one `entry` module for HarmonyOS. `EntryAbility` loads `pages/Index`; `ProjectionHomeAbility` loads the separate `pages/ProjectionHome` UI on the projection display.
- `Index` owns the phone UI, settings, diagnostics, and the `SessionController`. The controller coordinates the connection lifecycle and reports status through `SessionEvents`; keep protocol and transport code independent of UI components.
- The wireless connection path crosses several layers: `BluetoothIap2Server` receives RFCOMM bytes, `Iap2SenderSession` performs iAP2 session work using `protocol/Iap2Codec`, and the session controller coordinates the Wi-Fi join, AirPlay discovery/pairing/RTSP, and media startup. `WifiNetworkLease` keeps relevant sockets on the vehicle network.
- Projection spans the session controller and the projection ability: `CarPlayVirtualDisplay` manages the virtual display, video capture/encoding and audio components feed media to the car, and touch input is routed back to the receiver. Projection UI and display state are shared across abilities through `AppStorage`.
- `entry/src/main/cpp` contains portable C protocol/media/session cores plus separate N-API adapters. CMake builds `iap2codec`, `mediabytes`, `sessioncore`, and `projection`; ArkTS imports their shared-library interfaces through the declarations in `cpp/types`. Keep HarmonyOS-specific APIs at the N-API/ArkTS boundary rather than adding them to the portable cores.

## Repository conventions

- Keep lifecycle ownership in `SessionController`; use its generation-based lifecycle helpers to reject stale asynchronous callbacks after a stop or reconnect. Transport, socket, pairing, and display classes own their own listeners/resources and expose explicit cleanup.
- Cross-ability projection values use shared `AppStorage` keys. Preserve the existing key names and update both the publisher and consumer when changing a shared value.
- Emit protocol diagnostics through `ProtocolLogger` and `formatProtocolEvent` with the existing dotted event-name convention rather than adding ad hoc log formats.
- Keep native N-API declarations synchronized with the implementation and the matching `cpp/types/lib*/` TypeScript declarations. The portable C functions are also tested independently of HarmonyOS.
- Test coverage is split by boundary: `src/test/ProjectionBehavior.test.cjs` is a Node host suite, `src/test/native` tests portable C, `src/test` Hypium tests use test doubles where needed, and `src/ohosTest` covers device/N-API behavior.
- Treat signing material and machine-specific paths in build configuration and `certs/` as sensitive; do not copy their values into source, documentation, or logs.
