#include "projection_internal.h"

namespace {

std::mutex gScreenCaptureMutex;
std::unordered_map<int64_t, ScreenCaptureState*> gScreenCaptures;
std::atomic<int64_t> gNextScreenCaptureId{1};

int64_t NextScreenCaptureId() {
  return gNextScreenCaptureId.fetch_add(1);
}

void FinalizeScreenCapture(napi_env, void* data, void*) {
  delete static_cast<ScreenCaptureState*>(data);
}

void EmitScreenCaptureEvent(ScreenCaptureState* state, EncoderEvent* event) {
  if (state == nullptr || state->callback == nullptr || event == nullptr) {
    delete event;
    return;
  }
  const napi_status status = napi_call_threadsafe_function(state->callback, event, napi_tsfn_nonblocking);
  if (status != napi_ok) {
    delete event;
    if (status == napi_queue_full && !state->overflowReported.exchange(true)) {
      auto* overflow = new EncoderEvent();
      overflow->type = "overflow";
      overflow->message = "AVScreenCapture output callback queue is full; frames were dropped";
      if (napi_call_threadsafe_function(state->callback, overflow, napi_tsfn_nonblocking) != napi_ok) {
        delete overflow;
      }
    }
  }
}

void EmitScreenCaptureDiagnostic(ScreenCaptureState* state, const std::string& message) {
  auto* event = new EncoderEvent();
  event->type = "diagnostic";
  event->message = message;
  EmitScreenCaptureEvent(state, event);
}

void OnScreenCaptureError(OH_AVScreenCapture*, int32_t errorCode, void* userData) {
  auto* state = static_cast<ScreenCaptureState*>(userData);
  if (state == nullptr || !state->running.load()) {
    return;
  }
  auto* event = new EncoderEvent();
  event->type = "error";
  event->message = "AVScreenCapture error " + std::to_string(errorCode);
  EmitScreenCaptureEvent(state, event);
}

void OnScreenCaptureStateChange(OH_AVScreenCapture*, OH_AVScreenCaptureStateCode stateCode, void* userData) {
  auto* state = static_cast<ScreenCaptureState*>(userData);
  if (state == nullptr || !state->running.load()) {
    return;
  }
  if (stateCode == OH_SCREEN_CAPTURE_STATE_STARTED) {
    EmitScreenCaptureDiagnostic(state, "screen capture started after system consent");
    return;
  }
  if (stateCode == OH_SCREEN_CAPTURE_STATE_CANCELED) {
    auto* event = new EncoderEvent();
    event->type = "error";
    event->message = "Screen capture consent was canceled or denied";
    EmitScreenCaptureEvent(state, event);
    return;
  }
  if (stateCode == OH_SCREEN_CAPTURE_STATE_STOPPED_BY_USER ||
      stateCode == OH_SCREEN_CAPTURE_STATE_INTERRUPTED_BY_OTHER ||
      stateCode == OH_SCREEN_CAPTURE_STATE_STOPPED_BY_CALL ||
      stateCode == OH_SCREEN_CAPTURE_STATE_STOPPED_BY_USER_SWITCHES) {
    auto* event = new EncoderEvent();
    event->type = "error";
    event->message = "Screen capture stopped by system or user (state=" + std::to_string(stateCode) + ")";
    EmitScreenCaptureEvent(state, event);
    return;
  }
  EmitScreenCaptureDiagnostic(state, "screen capture state changed: " + std::to_string(stateCode));
}

int32_t DestroyScreenCapture(ScreenCaptureState* state, bool abortCallback, bool stopCapture) {
  if (state == nullptr) {
    return AV_SCREEN_CAPTURE_ERR_OK;
  }
  int32_t firstError = AV_SCREEN_CAPTURE_ERR_OK;
  state->running.store(false);
  if (state->capture != nullptr) {
    if (stopCapture) {
      const OH_AVSCREEN_CAPTURE_ErrCode stopResult = OH_AVScreenCapture_StopScreenCapture(state->capture);
      if (stopResult != AV_SCREEN_CAPTURE_ERR_OK) {
        firstError = static_cast<int32_t>(stopResult);
      }
    }
    const OH_AVSCREEN_CAPTURE_ErrCode releaseResult = OH_AVScreenCapture_Release(state->capture);
    if (firstError == AV_SCREEN_CAPTURE_ERR_OK && releaseResult != AV_SCREEN_CAPTURE_ERR_OK) {
      firstError = static_cast<int32_t>(releaseResult);
    }
    state->capture = nullptr;
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
  return firstError;
}

}  // namespace

napi_value StartScreenCapture(napi_env env, napi_callback_info info) {
  size_t argc = 7;
  napi_value args[7];
  if (napi_get_cb_info(env, info, &argc, args, nullptr, nullptr) != napi_ok || argc != 7) {
    return ThrowError(env, "startScreenCapture expects displayId, width, height, fps, bitrate, encoder handle, and callback");
  }
  int64_t displayId = -1;
  int64_t encoderId = 0;
  int32_t width = 0;
  int32_t height = 0;
  int32_t fps = 0;
  int32_t bitrate = 0;
  napi_valuetype callbackType;
  if (napi_get_value_int64(env, args[0], &displayId) != napi_ok ||
      !ReadInt32(env, args[1], &width) || !ReadInt32(env, args[2], &height) ||
      !ReadInt32(env, args[3], &fps) || !ReadInt32(env, args[4], &bitrate) ||
      napi_get_value_int64(env, args[5], &encoderId) != napi_ok ||
      napi_typeof(env, args[6], &callbackType) != napi_ok || callbackType != napi_function) {
    return ThrowError(env, "Invalid AVScreenCapture arguments");
  }
  if (displayId <= 0 || width < MIN_DIMENSION || width > MAX_VIDEO_WIDTH || height < MIN_DIMENSION ||
      height > MAX_VIDEO_HEIGHT || (width & 1) != 0 || (height & 1) != 0 || fps < 15 || fps > 60 ||
      bitrate < 500000 || bitrate > 20000000) {
    return ThrowError(env, "AVScreenCapture display, dimensions, frame rate, or bitrate are out of range");
  }
  {
    std::lock_guard<std::mutex> lock(gScreenCaptureMutex);
    if (!gScreenCaptures.empty()) {
      return ThrowError(env, "Only one active AVScreenCapture instance is supported");
    }
  }

  OHNativeWindow* encoderWindow = nullptr;
  if (!GetRunningEncoderWindow(encoderId, &encoderWindow)) {
    return ThrowError(env, "H.264 encoder input surface is not available");
  }

  auto* state = new ScreenCaptureState();
  state->id = NextScreenCaptureId();
  napi_value resourceName = MakeString(env, "CarPlayScreenCaptureOutput");
  if (napi_create_threadsafe_function(
          env, args[6], nullptr, resourceName, MAX_PENDING_FRAMES, 1, state,
          FinalizeScreenCapture, nullptr, CallJs, &state->callback) != napi_ok) {
    delete state;
    return ThrowError(env, "Unable to create AVScreenCapture output callback");
  }
  state->capture = OH_AVScreenCapture_Create();
  if (state->capture == nullptr) {
    DestroyScreenCapture(state, true, false);
    return ThrowError(env, "Unable to create AVScreenCapture instance");
  }
  OH_AVScreenCaptureConfig config{};
  config.captureMode = OH_CAPTURE_SPECIFIED_SCREEN;
  config.dataType = OH_ORIGINAL_STREAM;
  config.videoInfo.videoCapInfo.displayId = static_cast<uint64_t>(displayId);
  config.videoInfo.videoCapInfo.videoFrameWidth = width;
  config.videoInfo.videoCapInfo.videoFrameHeight = height;
  config.videoInfo.videoCapInfo.videoSource = OH_VIDEO_SOURCE_SURFACE_RGBA;
  OH_AVSCREEN_CAPTURE_ErrCode result = OH_AVScreenCapture_Init(state->capture, config);
  if (result != AV_SCREEN_CAPTURE_ERR_OK) {
    DestroyScreenCapture(state, true, false);
    return ThrowError(env, "AVScreenCapture_Init failed (code=" +
                               std::to_string(static_cast<int32_t>(result)) + ")");
  }
  result = OH_AVScreenCapture_SetStateCallback(state->capture, OnScreenCaptureStateChange, state);
  if (result == AV_SCREEN_CAPTURE_ERR_OK) {
    result = OH_AVScreenCapture_SetErrorCallback(state->capture, OnScreenCaptureError, state);
  }
  if (result != AV_SCREEN_CAPTURE_ERR_OK) {
    DestroyScreenCapture(state, true, false);
    return ThrowError(env, "Unable to register AVScreenCapture callbacks (code=" +
                               std::to_string(static_cast<int32_t>(result)) + ")");
  }

  state->running.store(true);
  {
    std::lock_guard<std::mutex> lock(gScreenCaptureMutex);
    gScreenCaptures.emplace(state->id, state);
  }
  result = OH_AVScreenCapture_StartScreenCaptureWithSurface(state->capture, encoderWindow);
  if (result != AV_SCREEN_CAPTURE_ERR_OK) {
    {
      std::lock_guard<std::mutex> lock(gScreenCaptureMutex);
      gScreenCaptures.erase(state->id);
    }
    DestroyScreenCapture(state, true, false);
    return ThrowError(env, "AVScreenCapture_StartScreenCaptureWithSurface failed (code=" +
                               std::to_string(static_cast<int32_t>(result)) + ")");
  }
  EmitScreenCaptureDiagnostic(state, "specified-screen capture requested with encoder surface: displayId=" +
                                         std::to_string(displayId) + ", size=" + std::to_string(width) + "x" +
                                         std::to_string(height));
  napi_value handle;
  napi_create_int64(env, state->id, &handle);
  return handle;
}

napi_value StopScreenCapture(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1];
  if (napi_get_cb_info(env, info, &argc, args, nullptr, nullptr) != napi_ok || argc != 1) {
    return ThrowError(env, "stopScreenCapture expects a capture handle");
  }
  int64_t handle = 0;
  if (napi_get_value_int64(env, args[0], &handle) != napi_ok) {
    return ThrowError(env, "Invalid AVScreenCapture handle");
  }
  ScreenCaptureState* state = nullptr;
  {
    std::lock_guard<std::mutex> lock(gScreenCaptureMutex);
    const auto found = gScreenCaptures.find(handle);
    if (found == gScreenCaptures.end()) {
      napi_value undefined;
      napi_get_undefined(env, &undefined);
      return undefined;
    }
    state = found->second;
    gScreenCaptures.erase(found);
  }
  const int32_t cleanupResult = DestroyScreenCapture(state, true, true);
  if (cleanupResult != AV_SCREEN_CAPTURE_ERR_OK) {
    return ThrowError(env, "AVScreenCapture stop or release failed (code=" + std::to_string(cleanupResult) + ")");
  }
  napi_value undefined;
  napi_get_undefined(env, &undefined);
  return undefined;
}
