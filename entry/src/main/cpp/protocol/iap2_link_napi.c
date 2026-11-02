#include "iap2_link.h"

#include <napi/native_api.h>

#define MAX_LINK_BUFFER_BYTES (1024u * 1024u)

napi_status iap2_register_control(napi_env env, napi_value exports);
napi_status tlv8_register(napi_env env, napi_value exports);

static napi_value fail(napi_env env, const char *message)
{
  napi_throw_error(env, NULL, message);
  return NULL;
}

/* N-API returns a pointer already adjusted for a typed array's byte offset. */
static int get_bytes(napi_env env, napi_value value, const uint8_t **bytes, size_t *length)
{
  bool is_typed_array = false;
  napi_typedarray_type type;
  void *data = NULL;
  napi_value buffer;
  size_t offset;
  if (napi_is_typedarray(env, value, &is_typed_array) != napi_ok || !is_typed_array ||
      napi_get_typedarray_info(env, value, &type, length, &data, &buffer, &offset) != napi_ok ||
      type != napi_uint8_array) {
    return 0;
  }
  *bytes = (const uint8_t *)data;
  return 1;
}

static napi_value encode_link(napi_env env, napi_callback_info info)
{
  size_t count = 5;
  napi_value args[5];
  uint32_t fields[4];
  const uint8_t *payload = NULL;
  size_t payload_length = 0;
  if (napi_get_cb_info(env, info, &count, args, NULL, NULL) != napi_ok || count != 5) {
    return fail(env, "iAP2 link encoder requires four header fields and a Uint8Array");
  }
  for (size_t index = 0; index < 4; ++index) {
    if (napi_get_value_uint32(env, args[index], &fields[index]) != napi_ok || fields[index] > 255) {
      return fail(env, "Invalid iAP2 link header field");
    }
  }
  if (!get_bytes(env, args[4], &payload, &payload_length) || payload_length > 65525u) {
    return fail(env, "iAP2 link frame is too large or has an invalid payload");
  }
  const size_t length = 9u + payload_length + (payload_length != 0 ? 1u : 0u);
  napi_value buffer;
  napi_value result;
  void *output = NULL;
  if (napi_create_arraybuffer(env, length, &output, &buffer) != napi_ok ||
      iap2_link_encode((uint8_t *)output, length, (uint8_t)fields[0], (uint8_t)fields[1],
                       (uint8_t)fields[2], (uint8_t)fields[3], payload, payload_length) != length ||
      napi_create_typedarray(env, napi_uint8_array, length, buffer, 0, &result) != napi_ok) {
    return fail(env, "Unable to encode iAP2 link frame");
  }
  return result;
}

static napi_value scan_link(napi_env env, napi_callback_info info)
{
  size_t count = 1;
  napi_value args[1];
  const uint8_t *bytes = NULL;
  size_t length = 0;
  if (napi_get_cb_info(env, info, &count, args, NULL, NULL) != napi_ok || count != 1 ||
      !get_bytes(env, args[0], &bytes, &length) || length > MAX_LINK_BUFFER_BYTES) {
    return fail(env, "Invalid or oversized iAP2 link input");
  }
  const iap2_link_scan_result scan = iap2_link_scan(bytes, length);
  const size_t values[3] = {scan.consumed, scan.frame_offset, scan.frame_length};
  napi_value result;
  if (napi_create_array_with_length(env, 3, &result) != napi_ok) {
    return fail(env, "Unable to allocate iAP2 scan result");
  }
  for (uint32_t index = 0; index < 3; ++index) {
    napi_value value;
    if (napi_create_uint32(env, (uint32_t)values[index], &value) != napi_ok ||
        napi_set_element(env, result, index, value) != napi_ok) {
      return fail(env, "Unable to create iAP2 scan result");
    }
  }
  return result;
}

static napi_value init(napi_env env, napi_value exports)
{
  const napi_property_descriptor properties[] = {
      {"encodeLink", NULL, encode_link, NULL, NULL, NULL, napi_default, NULL},
      {"scanLink", NULL, scan_link, NULL, NULL, NULL, napi_default, NULL}
  };
  if (napi_define_properties(env, exports, sizeof(properties) / sizeof(properties[0]), properties) != napi_ok ||
      iap2_register_control(env, exports) != napi_ok ||
      tlv8_register(env, exports) != napi_ok) {
    return NULL;
  }
  return exports;
}

NAPI_MODULE(iap2codec, init)