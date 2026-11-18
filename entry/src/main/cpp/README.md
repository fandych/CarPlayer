# Native Data Processing

## Layers

- `protocol/iap2_link.*` implements iAP2 link framing, checksum validation and stream resynchronization.
- `protocol/iap2_control.*` implements control messages and length-prefixed parameters.
- `protocol/tlv8.*` implements bounded TLV8 parsing, fragmentation and encoding for AirPlay pairing.
- `session/session_core.*` issues atomic 64-bit lifecycle generations so stale async callbacks can be rejected without routing identifiers through JavaScript numbers.
- `media/pcm.*` converts 16-bit PCM sample byte order.
- `media/h264.*` locates NAL units in Annex B, AVC configuration and length-prefixed data.
- `*_napi.c` validates and converts N-API values; protocol and media cores do not depend on HarmonyOS.
- ArkTS retains session state, asynchronous I/O, system services and UI. Stream buffers and typed result objects remain in the ArkTS adapters.

The scan functions report the bytes consumed and the offset and length of one complete frame. They retain incomplete input for the caller and skip invalid headers or checksums. The caller limits buffered input to 1 MiB. Encoding and parameter parsing check lengths before accessing data. N-API accepts `Uint8Array` views, including nonzero byte offsets, and returns new buffers.

TLV8 N-API decoding validates framing and performs continuation/duplicate-type handling natively. ArkTS only adapts the returned type ranges into a `Map`.

## Verification

On Windows, run `entry/src/test/native/run-tests.ps1` from the CarPlayer directory. Set `DEVECO_SDK_HOME` if DevEco Studio is installed in a nondefault location. The script compiles the pure C tests using the DevEco LLVM tools and writes temporary build artifacts under the system temporary directory.

Host Hypium tests explicitly inject a test-only ArkTS stand-in because the host runner cannot load HarmonyOS shared libraries. These tests do not validate native execution. The device test suite exercises the N-API boundary and must be run on an attached HarmonyOS device; an application or test-package build alone does not establish runtime or vehicle compatibility.