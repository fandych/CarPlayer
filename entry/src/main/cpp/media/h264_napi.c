#include "h264.h"

#include <napi/native_api.h>

#define MAX_H264_BYTES (4u * 1024u * 1024u)

static napi_value split_h264(napi_env env, napi_callback_info info)
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
      type != napi_uint8_array || length > MAX_H264_BYTES) {
    napi_throw_error(env, NULL, "H.264 input must be a Uint8Array no larger than 4 MiB");
    return NULL;
  }
  const size_t units = h264_split_units(input, length, NULL, 0);
  napi_value buffer;
  napi_value result;
  void *pairs = NULL;
  if (napi_create_arraybuffer(env, units * 2 * sizeof(uint32_t), &pairs, &buffer) != napi_ok ||
      h264_split_units(input, length, pairs, units) != units ||
      napi_create_typedarray(env, napi_uint32_array, units * 2, buffer, 0, &result) != napi_ok) {
    napi_throw_error(env, NULL, "Unable to split H.264 NAL units");
    return NULL;
  }
  return result;
}

napi_status media_register_h264(napi_env env, napi_value exports)
{
  const napi_property_descriptor properties[] = {
      {"splitH264", NULL, split_h264, NULL, NULL, NULL, napi_default, NULL}
  };
  return napi_define_properties(env, exports, 1, properties);
}