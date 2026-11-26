#ifndef CARPLAYER_PROJECTION_INTERNAL_H
#define CARPLAYER_PROJECTION_INTERNAL_H

#include <atomic>
#include <cstdint>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

#include <napi/native_api.h>
#include <multimedia/player_framework/native_avcapability.h>
#include <multimedia/player_framework/native_avbuffer.h>
#include <multimedia/player_framework/native_avbuffer_info.h>
#include <multimedia/player_framework/native_avcodec_base.h>
#include <multimedia/player_framework/native_avcodec_videoencoder.h>
#include <multimedia/player_framework/native_avformat.h>
#include <multimedia/player_framework/native_avscreen_capture.h>
#include <native_window/external_window.h>

constexpr size_t MAX_PENDING_FRAMES = 48;
constexpr int32_t MAX_ENCODED_BUFFER_BYTES = 4 * 1024 * 1024;
constexpr int32_t MIN_DIMENSION = 320;
constexpr int32_t MAX_VIDEO_WIDTH = 4096;
constexpr int32_t MAX_VIDEO_HEIGHT = 2160;

struct EncoderEvent {
  std::string type;
  std::string message;
  std::vector<uint8_t> data;
  int64_t timestampUs = 0;
  uint32_t flags = 0;
};

struct EncoderState {
  int64_t id = 0;
  OH_AVCodec* codec = nullptr;
  OHNativeWindow* inputWindow = nullptr;
  napi_threadsafe_function callback = nullptr;
  std::atomic<bool> running{false};
  std::atomic<bool> overflowReported{false};
};

struct ScreenCaptureState {
  int64_t id = 0;
  OH_AVScreenCapture* capture = nullptr;
  napi_threadsafe_function callback = nullptr;
  std::atomic<bool> running{false};
  std::atomic<bool> overflowReported{false};
};

napi_value MakeString(napi_env env, const std::string& value);
void SetNamed(napi_env env, napi_value object, const char* name, napi_value value);
bool ReadInt32(napi_env env, napi_value value, int32_t* result);
napi_value ThrowError(napi_env env, const std::string& message);
void CallJs(napi_env env, napi_value function, void* context, void* data);

bool RequestSyncFrame(EncoderState* state);
void EmitEvent(EncoderState* state, EncoderEvent* event);
void EmitDiagnostic(EncoderState* state, const std::string& message);
void DestroyEncoder(EncoderState* state, bool abortCallback);
bool HasActiveEncoder();
bool RegisterEncoder(EncoderState* state);
EncoderState* RemoveEncoder(int64_t id);
EncoderState* FindEncoder(int64_t id);
int64_t NextEncoderId();
void RegisterEncoderCallbacks(OH_AVCodec* codec, EncoderState* state, OH_AVErrCode* result);
void FinalizeEncoderCallback(napi_env env, void* data, void* hint);
bool GetRunningEncoderWindow(int64_t id, OHNativeWindow** window);
napi_value IsVideoEncoderSizeSupported(napi_env env, napi_callback_info info);
napi_value CreateVideoEncoder(napi_env env, napi_callback_info info);
napi_value StopVideoEncoder(napi_env env, napi_callback_info info);
napi_value RequestKeyFrame(napi_env env, napi_callback_info info);
napi_value StartScreenCapture(napi_env env, napi_callback_info info);
napi_value StopScreenCapture(napi_env env, napi_callback_info info);

#endif
