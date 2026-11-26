# Native Data Processing

## Layers

- ArkTS implements iAP2 link framing, control messages, parameters and bounded TLV8 parsing/encoding in `ets/protocol` and `ets/airplay`.
- ArkTS issues and validates decimal 64-bit lifecycle-generation tokens so stale async callbacks can be rejected without JavaScript number precision loss.
- `projection_napi.cpp` adapts HarmonyOS screen-capture and video-encoder APIs to ArkTS.
- ArkTS implements PCM byte-order conversion and H.264 NAL-unit splitting; session state, asynchronous I/O, system services and UI also remain in ArkTS.

The scan functions report the bytes consumed and the offset and length of one complete frame. They retain incomplete input for the caller and skip invalid headers or checksums. The caller limits buffered input to 1 MiB. Encoding and parameter parsing check lengths before accessing data. N-API accepts `Uint8Array` views, including nonzero byte offsets, and returns new buffers.

ArkTS validates TLV8 framing and performs continuation/duplicate-type handling directly.

## Verification

The host Node behavior suite tests ArkTS protocol and lifecycle behavior. The device test suite exercises the projection N-API boundary and must be run on an attached HarmonyOS device; an application or test-package build alone does not establish runtime or vehicle compatibility.