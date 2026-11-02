#include "iap2_control.h"

#include <napi/native_api.h>

#define MAX_CONTROL_BUFFER_BYTES (1024u * 1024u)

static napi_value fail(napi_env env, const char *message)
{
  napi_throw_error(env, NULL, message);
  return NULL;
}

static int get_bytes(napi_env env, napi_value value, const uint8_t **bytes, size_t *length)
{
  bool is_typed_array = false;
  napi_typedarray_type type;
  void *data = NULL;
  napi_value buffer;
  size_t offset;
  if (napi_is_typedarray(env, value, &is_typed_array) != napi_ok || !is_typed_array ||
      napi_get_typedarray_info(env, value, &type, length, &data, &buffer, &offset) != napi_ok ||
      type != napi_uint8_array) return 0;
  *bytes = (const uint8_t *)data;
  return 1;
}

static napi_value encode(napi_env env, napi_callback_info info, bool control)
{
  size_t count = 2;
  napi_value args[2];
  uint32_t id;
  const uint8_t *input = NULL;
  size_t input_length = 0;
  const size_t header = control ? 6u : 4u;
  if (napi_get_cb_info(env, info, &count, args, NULL, NULL) != napi_ok || count != 2 ||
      napi_get_value_uint32(env, args[0], &id) != napi_ok || id > 65535u ||
      !get_bytes(env, args[1], &input, &input_length) || input_length > 65535u - header) {
    return fail(env, "Invalid or oversized iAP2 control message or parameter");
  }
  const size_t length = header + input_length;
  void *output = NULL;
  napi_value buffer;
  napi_value result;
  if (napi_create_arraybuffer(env, length, &output, &buffer) != napi_ok) {
    return fail(env, "Unable to allocate iAP2 encoded data");
  }
  const size_t encoded = control ?
      iap2_control_encode(output, length, (uint16_t)id, input, input_length) :
      iap2_parameter_encode(output, length, (uint16_t)id, input, input_length);
  if (encoded != length || napi_create_typedarray(env, napi_uint8_array, length, buffer, 0, &result) != napi_ok) {
    return fail(env, "Unable to encode iAP2 data");
  }
  return result;
}

static napi_value encode_control(napi_env env, napi_callback_info info)
{
  return encode(env, info, true);
}

static napi_value encode_parameter(napi_env env, napi_callback_info info)
{
  return encode(env, info, false);
}

static napi_value scan_control(napi_env env, napi_callback_info info)
{
  size_t count = 1;
  napi_value args[1];
  const uint8_t *bytes = NULL;
  size_t length = 0;
  if (napi_get_cb_info(env, info, &count, args, NULL, NULL) != napi_ok || count != 1 ||
      !get_bytes(env, args[0], &bytes, &length) || length > MAX_CONTROL_BUFFER_BYTES) {
    return fail(env, "Invalid or oversized iAP2 control input");
  }
  const iap2_control_scan_result scan = iap2_control_scan(bytes, length);
  const size_t values[3] = {scan.consumed, scan.frame_offset, scan.frame_length};
  napi_value result;
  if (napi_create_array_with_length(env, 3, &result) != napi_ok) return fail(env, "Unable to allocate scan result");
  for (uint32_t index = 0; index < 3; ++index) {
    napi_value value;
    if (napi_create_uint32(env, (uint32_t)values[index], &value) != napi_ok ||
        napi_set_element(env, result, index, value) != napi_ok) return fail(env, "Unable to create scan result");
  }
  return result;
}

/* Return flat triples so ArkTS can construct its existing typed parameter objects. */
static napi_value parse_parameters(napi_env env, napi_callback_info info)
{
  size_t count = 1;
  napi_value args[1];
  const uint8_t *bytes = NULL;
  size_t length = 0;
  if (napi_get_cb_info(env, info, &count, args, NULL, NULL) != napi_ok || count != 1 ||
      !get_bytes(env, args[0], &bytes, &length) || length > MAX_CONTROL_BUFFER_BYTES) {
    return fail(env, "Invalid or oversized iAP2 parameter input");
  }
  size_t offset = 0, value_offset = 0, value_length = 0, parameters = 0;
  uint16_t id = 0;
  int status;
  while ((status = iap2_parameter_next(bytes, length, &offset, &id, &value_offset, &value_length)) == 1) ++parameters;
  if (status < 0) return fail(env, "Malformed iAP2 parameter length or trailing bytes");
  napi_value result;
  if (napi_create_array_with_length(env, parameters * 3, &result) != napi_ok) {
    return fail(env, "Unable to allocate iAP2 parameters");
  }
  offset = 0;
  uint32_t index = 0;
  while (iap2_parameter_next(bytes, length, &offset, &id, &value_offset, &value_length) == 1) {
    const uint32_t values[3] = {id, (uint32_t)value_offset, (uint32_t)value_length};
    for (size_t field = 0; field < 3; ++field) {
      napi_value value;
      if (napi_create_uint32(env, values[field], &value) != napi_ok ||
          napi_set_element(env, result, index++, value) != napi_ok) return fail(env, "Unable to create iAP2 parameters");
    }
  }
  return result;
}

napi_status iap2_register_control(napi_env env, napi_value exports)
{
  const napi_property_descriptor properties[] = {
      {"encodeControl", NULL, encode_control, NULL, NULL, NULL, napi_default, NULL},
      {"encodeParameter", NULL, encode_parameter, NULL, NULL, NULL, napi_default, NULL},
      {"scanControl", NULL, scan_control, NULL, NULL, NULL, napi_default, NULL},
      {"parseParameters", NULL, parse_parameters, NULL, NULL, NULL, napi_default, NULL}
  };
  return napi_define_properties(env, exports, sizeof(properties) / sizeof(properties[0]), properties);
}