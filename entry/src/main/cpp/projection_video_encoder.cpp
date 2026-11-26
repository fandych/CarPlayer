#include "projection_internal.h"

napi_value IsVideoEncoderSizeSupported(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value args[2];
  if (napi_get_cb_info(env, info, &argc, args, nullptr, nullptr) != napi_ok || argc != 2) {
    return ThrowError(env, "isVideoEncoderSizeSupported expects width and height");
  }
  int32_t width = 0;
  int32_t height = 0;
  if (!ReadInt32(env, args[0], &width) || !ReadInt32(env, args[1], &height)) {
    return ThrowError(env, "Invalid H.264 encoder size arguments");
  }
  bool supported = false;
  if (width >= MIN_DIMENSION && width <= MAX_VIDEO_WIDTH && height >= MIN_DIMENSION &&
      height <= MAX_VIDEO_HEIGHT && (width & 1) == 0 && (height & 1) == 0) {
    OH_AVCapability* capability = OH_AVCodec_GetCapability("video/avc", true);
    supported = capability != nullptr && OH_AVCapability_IsVideoSizeSupported(capability, width, height);
  }
  napi_value result;
  napi_get_boolean(env, supported, &result);
  return result;
}

void DestroyEncoder(EncoderState* state, bool abortCallback) {
  if (state == nullptr) {
    return;
  }
  state->running.store(false);
  if (state->codec != nullptr) {
    OH_VideoEncoder_Stop(state->codec);
    OH_VideoEncoder_Destroy(state->codec);
    state->codec = nullptr;
  }
  if (state->inputWindow != nullptr) {
    OH_NativeWindow_DestroyNativeWindow(state->inputWindow);
    state->inputWindow = nullptr;
  }
  if (state->callback != nullptr) {
    napi_release_threadsafe_function(
        state->callback,
        abortCallback ? napi_tsfn_abort : napi_tsfn_release
    );
    state->callback = nullptr;
  } else {
    delete state;
  }
}

napi_value CreateVideoEncoder(napi_env env, napi_callback_info info) {
  size_t argc = 5;
  napi_value args[5];
  if (napi_get_cb_info(env, info, &argc, args, nullptr, nullptr) != napi_ok || argc != 5) {
    return ThrowError(env, "createVideoEncoder expects width, height, fps, bitrate, and callback");
  }
  int32_t width = 0;
  int32_t height = 0;
  int32_t fps = 0;
  int32_t bitrate = 0;
  napi_valuetype callbackType;
  if (!ReadInt32(env, args[0], &width) || !ReadInt32(env, args[1], &height) ||
      !ReadInt32(env, args[2], &fps) || !ReadInt32(env, args[3], &bitrate) ||
      napi_typeof(env, args[4], &callbackType) != napi_ok || callbackType != napi_function) {
    return ThrowError(env, "Invalid H.264 encoder arguments");
  }
  if (width < MIN_DIMENSION || width > MAX_VIDEO_WIDTH || height < MIN_DIMENSION ||
      height > MAX_VIDEO_HEIGHT || (width & 1) != 0 || (height & 1) != 0 ||
      fps < 15 || fps > 60 || bitrate < 500000 || bitrate > 20000000) {
    return ThrowError(env, "H.264 encoder dimensions, frame rate, or bitrate are out of range");
  }
  if (HasActiveEncoder()) {
    return ThrowError(env, "Only one active CarPlay video encoder is supported");
  }

  auto* state = new EncoderState();
  state->id = NextEncoderId();
  napi_value resourceName = MakeString(env, "CarPlayH264Output");
  if (napi_create_threadsafe_function(
          env, args[4], nullptr, resourceName, MAX_PENDING_FRAMES, 1, state,
          FinalizeEncoderCallback, nullptr, CallJs, &state->callback) != napi_ok) {
    delete state;
    return ThrowError(env, "Unable to create H.264 output callback");
  }

  state->codec = OH_VideoEncoder_CreateByMime("video/avc");
  if (state->codec == nullptr) {
    DestroyEncoder(state, true);
    return ThrowError(env, "HarmonyOS has no available H.264 video encoder");
  }
  EmitDiagnostic(state, "codec created: mime=video/avc");

  OH_AVErrCode callbackResult = AV_ERR_OK;
  RegisterEncoderCallbacks(state->codec, state, &callbackResult);
  if (callbackResult != AV_ERR_OK) {
    DestroyEncoder(state, true);
    return ThrowError(env, "Unable to register H.264 encoder callbacks (code=" +
                               std::to_string(static_cast<int32_t>(callbackResult)) + ")");
  }
  EmitDiagnostic(state, "encoder callbacks registered");

  OH_AVFormat* format = OH_AVFormat_CreateVideoFormat("video/avc", width, height);
  if (format == nullptr) {
    DestroyEncoder(state, true);
    return ThrowError(env, "Unable to allocate H.264 encoder format");
  }
  EmitDiagnostic(state, "video format allocated: width=" + std::to_string(width) +
                             ", height=" + std::to_string(height));
  const auto failFormat = [&](const char* parameter) -> napi_value {
    OH_AVFormat_Destroy(format);
    DestroyEncoder(state, true);
    return ThrowError(env, std::string("Unable to set H.264 encoder ") + parameter +
                               " (width=" + std::to_string(width) +
                               ", height=" + std::to_string(height) +
                               ", fps=" + std::to_string(fps) +
                               ", bitrate=" + std::to_string(bitrate) + ")");
  };
  if (!OH_AVFormat_SetLongValue(format, OH_MD_KEY_BITRATE, static_cast<int64_t>(bitrate))) {
    return failFormat("bitrate");
  }
  EmitDiagnostic(state, "bitrate accepted as int64: " + std::to_string(bitrate));
  if (!OH_AVFormat_SetDoubleValue(format, OH_MD_KEY_FRAME_RATE, static_cast<double>(fps))) {
    return failFormat("frame rate");
  }
  EmitDiagnostic(state, "frame rate accepted: " + std::to_string(fps));
  if (!OH_AVFormat_SetIntValue(format, OH_MD_KEY_I_FRAME_INTERVAL, 1)) {
    return failFormat("I-frame interval");
  }
  EmitDiagnostic(state, "I-frame interval accepted: 1 second");
  const OH_AVErrCode configureResult = OH_VideoEncoder_Configure(state->codec, format);
  OH_AVFormat_Destroy(format);
  if (configureResult != AV_ERR_OK) {
    DestroyEncoder(state, true);
    return ThrowError(env, "Unable to configure H.264 video encoder (code=" +
                               std::to_string(static_cast<int32_t>(configureResult)) + ")");
  }
  EmitDiagnostic(state, "encoder configured successfully");

  const OH_AVErrCode surfaceResult = OH_VideoEncoder_GetSurface(state->codec, &state->inputWindow);
  if (surfaceResult != AV_ERR_OK || state->inputWindow == nullptr) {
    DestroyEncoder(state, true);
    return ThrowError(env, "Unable to obtain H.264 encoder input surface (code=" +
                               std::to_string(static_cast<int32_t>(surfaceResult)) + ")");
  }
  EmitDiagnostic(state, "encoder input surface obtained");
  uint64_t surfaceId = 0;
  const int32_t surfaceIdResult = OH_NativeWindow_GetSurfaceId(state->inputWindow, &surfaceId);
  if (surfaceIdResult != 0) {
    DestroyEncoder(state, true);
    return ThrowError(env, "Unable to obtain H.264 encoder surface ID (code=" +
                               std::to_string(surfaceIdResult) + ")");
  }
  EmitDiagnostic(state, "encoder surface ID obtained: " + std::to_string(surfaceId));
  const OH_AVErrCode prepareResult = OH_VideoEncoder_Prepare(state->codec);
  if (prepareResult != AV_ERR_OK) {
    DestroyEncoder(state, true);
    return ThrowError(env, "Unable to prepare H.264 video encoder (code=" +
                               std::to_string(static_cast<int32_t>(prepareResult)) + ")");
  }
  EmitDiagnostic(state, "encoder prepared successfully");
  state->running.store(true);
  if (!RegisterEncoder(state)) {
    DestroyEncoder(state, true);
    return ThrowError(env, "Only one active CarPlay video encoder is supported");
  }
  const OH_AVErrCode startResult = OH_VideoEncoder_Start(state->codec);
  if (startResult != AV_ERR_OK) {
    RemoveEncoder(state->id);
    DestroyEncoder(state, true);
    return ThrowError(env, "Unable to start H.264 video encoder (code=" +
                               std::to_string(static_cast<int32_t>(startResult)) + ")");
  }
  EmitDiagnostic(state, "encoder started successfully");

  napi_value result;
  napi_create_object(env, &result);
  napi_value handle;
  napi_create_int64(env, state->id, &handle);
  SetNamed(env, result, "handle", handle);
  SetNamed(env, result, "surfaceId", MakeString(env, std::to_string(surfaceId)));
  return result;
}

napi_value StopVideoEncoder(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1];
  if (napi_get_cb_info(env, info, &argc, args, nullptr, nullptr) != napi_ok || argc != 1) {
    return ThrowError(env, "stopVideoEncoder expects an encoder handle");
  }
  int64_t handle = 0;
  if (napi_get_value_int64(env, args[0], &handle) != napi_ok) {
    return ThrowError(env, "Invalid H.264 encoder handle");
  }
  EncoderState* state = RemoveEncoder(handle);
  if (state != nullptr) {
    DestroyEncoder(state, true);
  }
  napi_value undefined;
  napi_get_undefined(env, &undefined);
  return undefined;
}

napi_value RequestKeyFrame(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1];
  if (napi_get_cb_info(env, info, &argc, args, nullptr, nullptr) != napi_ok || argc != 1) {
    return ThrowError(env, "requestKeyFrame expects an encoder handle");
  }
  int64_t handle = 0;
  if (napi_get_value_int64(env, args[0], &handle) != napi_ok) {
    return ThrowError(env, "Invalid H.264 encoder handle");
  }
  EncoderState* state = FindEncoder(handle);
  if (state == nullptr || state->codec == nullptr || !state->running.load()) {
    return ThrowError(env, "H.264 encoder is not running");
  }
  if (!RequestSyncFrame(state)) {
    return ThrowError(env, "Unable to request H.264 key frame");
  }
  napi_value success;
  napi_get_boolean(env, true, &success);
  return success;
}
