#include "pcm.h"

#include <napi/native_api.h>

#define MAX_PCM_BYTES (1024u * 1024u)

napi_status media_register_h264(napi_env env, napi_value exports);

static napi_value swap_pcm(napi_env env, napi_callback_info info)
{
  size_t count = 1;
  napi_value args[1];
  bool typed_array = false;
  napi_typedarray_type type;
  void *input = NULL;
  size_t length = 0, offset = 0;
  napi_value input_buffer;
  if (napi_get_cb_info(env, info, &count, args, NULL, NULL) != napi_ok || count != 1 ||
      napi_is_typedarray(env, args[0], &typed_array) != napi_ok || !typed_array ||
      napi_get_typedarray_info(env, args[0], &type, &length, &input, &input_buffer, &offset) != napi_ok ||
      type != napi_uint8_array || length > MAX_PCM_BYTES || (length & 1u) != 0) {
    napi_throw_error(env, NULL, "PCM input must be an even-length Uint8Array no larger than 1 MiB");
    return NULL;
  }
  napi_value output_buffer;
  napi_value result;
  void *output = NULL;
  if (napi_create_arraybuffer(env, length, &output, &output_buffer) != napi_ok ||
      !pcm_swap_s16(output, input, length) ||
      napi_create_typedarray(env, napi_uint8_array, length, output_buffer, 0, &result) != napi_ok) {
    napi_throw_error(env, NULL, "Unable to convert PCM samples");
    return NULL;
  }
  return result;
}

static napi_value init(napi_env env, napi_value exports)
{
  const napi_property_descriptor properties[] = {
      {"swapPcmS16", NULL, swap_pcm, NULL, NULL, NULL, napi_default, NULL}
  };
  return napi_define_properties(env, exports, 1, properties) == napi_ok &&
      media_register_h264(env, exports) == napi_ok ? exports : NULL;
}

NAPI_MODULE(mediabytes, init)