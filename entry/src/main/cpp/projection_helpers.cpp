#include "projection_internal.h"

void SetNamed(napi_env env, napi_value object, const char* name, napi_value value) {
  napi_set_named_property(env, object, name, value);
}

napi_value MakeString(napi_env env, const std::string& value) {
  napi_value result;
  napi_create_string_utf8(env, value.c_str(), value.size(), &result);
  return result;
}

void CallJs(napi_env env, napi_value function, void*, void* data) {
  std::unique_ptr<EncoderEvent> event(static_cast<EncoderEvent*>(data));
  if (env == nullptr || function == nullptr || event == nullptr) {
    return;
  }

  napi_value object;
  napi_create_object(env, &object);
  SetNamed(env, object, "type", MakeString(env, event->type));
  if (!event->message.empty()) {
    SetNamed(env, object, "message", MakeString(env, event->message));
  }
  napi_value timestamp;
  napi_create_int64(env, event->timestampUs, &timestamp);
  SetNamed(env, object, "timestampUs", timestamp);
  napi_value flags;
  napi_create_uint32(env, event->flags, &flags);
  SetNamed(env, object, "flags", flags);

  if (!event->data.empty()) {
    napi_value arrayBuffer;
    void* arrayBufferData = nullptr;
    if (napi_create_arraybuffer(env, event->data.size(), &arrayBufferData, &arrayBuffer) != napi_ok) {
      return;
    }
    std::memcpy(arrayBufferData, event->data.data(), event->data.size());
    napi_value bytes;
    if (napi_create_typedarray(env, napi_uint8_array, event->data.size(), arrayBuffer, 0, &bytes) != napi_ok) {
      return;
    }
    SetNamed(env, object, "data", bytes);
  }

  napi_value global;
  napi_get_global(env, &global);
  napi_value ignored;
  napi_call_function(env, global, function, 1, &object, &ignored);
}

bool ReadInt32(napi_env env, napi_value value, int32_t* result) {
  return napi_get_value_int32(env, value, result) == napi_ok;
}

napi_value ThrowError(napi_env env, const std::string& message) {
  napi_throw_error(env, nullptr, message.c_str());
  return nullptr;
}
