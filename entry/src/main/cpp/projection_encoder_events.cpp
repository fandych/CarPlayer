#include "projection_internal.h"

namespace {

std::mutex gEncoderMutex;
std::unordered_map<int64_t, EncoderState*> gEncoders;
std::atomic<int64_t> gNextEncoderId{1};

void FinalizeEncoder(napi_env, void* data, void*) {
  delete static_cast<EncoderState*>(data);
}

void OnCodecError(OH_AVCodec*, int32_t errorCode, void* userData) {
  auto* state = static_cast<EncoderState*>(userData);
  if (state == nullptr || !state->running.load()) {
    return;
  }
  auto* event = new EncoderEvent();
  event->type = "error";
  event->message = "Video encoder error " + std::to_string(errorCode);
  EmitEvent(state, event);
}

void OnStreamChanged(OH_AVCodec*, OH_AVFormat*, void* userData) {
  auto* state = static_cast<EncoderState*>(userData);
  if (state == nullptr || !state->running.load()) {
    return;
  }
  auto* event = new EncoderEvent();
  event->type = "streamChanged";
  EmitEvent(state, event);
}

void OnOutputBuffer(OH_AVCodec* codec, uint32_t index, OH_AVBuffer* buffer, void* userData) {
  auto* state = static_cast<EncoderState*>(userData);
  if (state == nullptr || buffer == nullptr) {
    if (codec != nullptr) {
      OH_VideoEncoder_FreeOutputBuffer(codec, index);
    }
    return;
  }

  OH_AVCodecBufferAttr attributes{};
  const OH_AVErrCode attrResult = OH_AVBuffer_GetBufferAttr(buffer, &attributes);
  uint8_t* address = OH_AVBuffer_GetAddr(buffer);
  if (state->running.load() && attrResult == AV_ERR_OK && address != nullptr &&
      attributes.offset >= 0 && attributes.size > 0 && attributes.size <= MAX_ENCODED_BUFFER_BYTES) {
    auto* event = new EncoderEvent();
    event->type = (attributes.flags & AVCODEC_BUFFER_FLAGS_CODEC_DATA) != 0 ? "codecConfig" : "frame";
    event->timestampUs = attributes.pts;
    event->flags = attributes.flags;
    event->data.assign(address + attributes.offset, address + attributes.offset + attributes.size);
    EmitEvent(state, event);
  } else if (state->running.load()) {
    auto* event = new EncoderEvent();
    event->type = "error";
    event->message = "H.264 encoder returned an invalid or oversized output buffer";
    EmitEvent(state, event);
  }
  OH_VideoEncoder_FreeOutputBuffer(codec, index);
}

}  // namespace

bool RequestSyncFrame(EncoderState* state) {
  if (state == nullptr || state->codec == nullptr || !state->running.load()) {
    return false;
  }
  OH_AVFormat* parameter = OH_AVFormat_Create();
  if (parameter == nullptr) {
    return false;
  }
  const bool setOk = OH_AVFormat_SetIntValue(parameter, OH_MD_KEY_REQUEST_I_FRAME, 1);
  const OH_AVErrCode result = setOk ? OH_VideoEncoder_SetParameter(state->codec, parameter) : AV_ERR_INVALID_VAL;
  OH_AVFormat_Destroy(parameter);
  return result == AV_ERR_OK;
}

void EmitEvent(EncoderState* state, EncoderEvent* event) {
  if (state == nullptr || state->callback == nullptr || event == nullptr) {
    delete event;
    return;
  }
  const napi_status status = napi_call_threadsafe_function(state->callback, event, napi_tsfn_nonblocking);
  if (status != napi_ok) {
    delete event;
    if (status == napi_queue_full) {
      RequestSyncFrame(state);
    }
    if (status == napi_queue_full && !state->overflowReported.exchange(true)) {
      auto* overflow = new EncoderEvent();
      overflow->type = "overflow";
      overflow->message = "H.264 output callback queue is full; frames were dropped";
      if (napi_call_threadsafe_function(state->callback, overflow, napi_tsfn_nonblocking) != napi_ok) {
        delete overflow;
      }
    }
  }
}

void EmitDiagnostic(EncoderState* state, const std::string& message) {
  auto* event = new EncoderEvent();
  event->type = "diagnostic";
  event->message = message;
  EmitEvent(state, event);
}

bool GetRunningEncoderWindow(int64_t id, OHNativeWindow** window) {
  std::lock_guard<std::mutex> lock(gEncoderMutex);
  const auto found = gEncoders.find(id);
  if (found == gEncoders.end() || !found->second->running.load() || window == nullptr) {
    return false;
  }
  *window = found->second->inputWindow;
  return *window != nullptr;
}

bool RegisterEncoder(EncoderState* state) {
  std::lock_guard<std::mutex> lock(gEncoderMutex);
  if (!gEncoders.empty()) {
    return false;
  }
  gEncoders.emplace(state->id, state);
  return true;
}

bool HasActiveEncoder() {
  std::lock_guard<std::mutex> lock(gEncoderMutex);
  return !gEncoders.empty();
}

EncoderState* RemoveEncoder(int64_t id) {
  std::lock_guard<std::mutex> lock(gEncoderMutex);
  const auto found = gEncoders.find(id);
  if (found == gEncoders.end()) {
    return nullptr;
  }
  EncoderState* state = found->second;
  gEncoders.erase(found);
  return state;
}

EncoderState* FindEncoder(int64_t id) {
  std::lock_guard<std::mutex> lock(gEncoderMutex);
  const auto found = gEncoders.find(id);
  return found == gEncoders.end() ? nullptr : found->second;
}

int64_t NextEncoderId() {
  return gNextEncoderId.fetch_add(1);
}

void RegisterEncoderCallbacks(OH_AVCodec* codec, EncoderState* state, OH_AVErrCode* result) {
  const OH_AVCodecCallback callbacks = {
      .onError = OnCodecError,
      .onStreamChanged = OnStreamChanged,
      .onNeedInputBuffer = nullptr,
      .onNewOutputBuffer = OnOutputBuffer
  };
  *result = OH_VideoEncoder_RegisterCallback(codec, callbacks, state);
}

void FinalizeEncoderCallback(napi_env, void* data, void*) {
  FinalizeEncoder(nullptr, data, nullptr);
}
