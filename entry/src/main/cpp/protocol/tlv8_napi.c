#include "tlv8.h"

#include <napi/native_api.h>
#include <stdlib.h>

#define MAX_TLV8_BUFFER_BYTES (1024u * 1024u)

static napi_value fail(napi_env env, const char *message)
{
  napi_throw_error(env, NULL, message);
  return NULL;
}

static int get_uint8_array(napi_env env, napi_value value, const uint8_t **bytes, size_t *length)
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

static napi_value encode_tlv8(napi_env env, napi_callback_info info)
{
  size_t argc = 2;
  napi_value args[2];
  const uint8_t *types = NULL;
  size_t count = 0;
  bool is_array = false;
  uint32_t values_count = 0;
  uint8_t **values = NULL;
  size_t *lengths = NULL;
  size_t encoded_length = 0;
  napi_value output_buffer;
  napi_value result;
  void *output = NULL;
  if (napi_get_cb_info(env, info, &argc, args, NULL, NULL) != napi_ok || argc != 2 ||
      !get_uint8_array(env, args[0], &types, &count) || count > MAX_TLV8_BUFFER_BYTES ||
      napi_is_array(env, args[1], &is_array) != napi_ok || !is_array ||
      napi_get_array_length(env, args[1], &values_count) != napi_ok || values_count != count) {
    return fail(env, "Invalid TLV8 types or values");
  }
  values = (uint8_t **)calloc(count == 0 ? 1 : count, sizeof(uint8_t *));
  lengths = (size_t *)calloc(count == 0 ? 1 : count, sizeof(size_t));
  if (values == NULL || lengths == NULL) {
    free(values);
    free(lengths);
    return fail(env, "Unable to allocate TLV8 encoder state");
  }
  for (uint32_t index = 0; index < values_count; ++index) {
    napi_value value;
    const uint8_t *value_bytes = NULL;
    if (napi_get_element(env, args[1], index, &value) != napi_ok ||
        !get_uint8_array(env, value, &value_bytes, &lengths[index]) ||
        lengths[index] > MAX_TLV8_BUFFER_BYTES) {
      free(values);
      free(lengths);
      return fail(env, "TLV8 values must be Uint8Array instances within the size limit");
    }
    values[index] = (uint8_t *)value_bytes;
  }
  encoded_length = tlv8_encoded_size(types, (const uint8_t *const *)values, lengths, count);
  if (encoded_length == (size_t)-1 || encoded_length > MAX_TLV8_BUFFER_BYTES ||
      napi_create_arraybuffer(env, encoded_length, &output, &output_buffer) != napi_ok) {
    free(values);
    free(lengths);
    return fail(env, "Invalid or oversized TLV8 message");
  }
  if (tlv8_encode((uint8_t *)output, encoded_length, types,
                  (const uint8_t *const *)values, lengths, count) != encoded_length ||
      napi_create_typedarray(env, napi_uint8_array, encoded_length, output_buffer, 0, &result) != napi_ok) {
    free(values);
    free(lengths);
    return fail(env, "Unable to encode TLV8 message");
  }
  free(values);
  free(lengths);
  return result;
}

static napi_value decode_tlv8(napi_env env, napi_callback_info info)
{
  size_t argc = 1;
  napi_value args[1];
  const uint8_t *input = NULL;
  size_t input_length = 0;
  size_t count = 0;
  size_t value_length = 0;
  size_t decoded_count = 0;
  size_t decoded_value_length = 0;
  tlv8_range *ranges = NULL;
  uint8_t *values = NULL;
  napi_value result;
  napi_value ranges_buffer;
  napi_value ranges_array;
  napi_value values_buffer;
  napi_value values_array;
  void *ranges_output = NULL;
  void *values_output = NULL;
  if (napi_get_cb_info(env, info, &argc, args, NULL, NULL) != napi_ok || argc != 1 ||
      !get_uint8_array(env, args[0], &input, &input_length) ||
      !tlv8_decode(input, input_length, NULL, 0, NULL, 0, &count, &value_length) ||
      count > UINT32_MAX / 3u || value_length > MAX_TLV8_BUFFER_BYTES) {
    return fail(env, "Invalid or malformed TLV8 input");
  }
  ranges = (tlv8_range *)calloc(count == 0 ? 1 : count, sizeof(tlv8_range));
  values = (uint8_t *)calloc(value_length == 0 ? 1 : value_length, sizeof(uint8_t));
  if (ranges == NULL || values == NULL ||
      !tlv8_decode(input, input_length, ranges, count, values, value_length,
                   &decoded_count, &decoded_value_length) ||
      decoded_count != count || decoded_value_length != value_length ||
      napi_create_arraybuffer(env, count * 3u * sizeof(uint32_t), &ranges_output, &ranges_buffer) != napi_ok ||
      napi_create_arraybuffer(env, value_length, &values_output, &values_buffer) != napi_ok ||
      napi_create_object(env, &result) != napi_ok) {
    free(ranges);
    free(values);
    return fail(env, "Unable to decode TLV8 input");
  }
  uint32_t *triples = (uint32_t *)ranges_output;
  for (size_t index = 0; index < count; ++index) {
    triples[index * 3u] = ranges[index].type;
    triples[index * 3u + 1u] = (uint32_t)ranges[index].value_offset;
    triples[index * 3u + 2u] = (uint32_t)ranges[index].value_length;
  }
  if ((value_length != 0 && values_output == NULL) ||
      (value_length != 0 && napi_create_typedarray(env, napi_uint8_array, value_length,
                                                   values_buffer, 0, &values_array) != napi_ok) ||
      napi_create_typedarray(env, napi_uint32_array, count * 3u, ranges_buffer, 0, &ranges_array) != napi_ok ||
      napi_set_named_property(env, result, "ranges", ranges_array) != napi_ok ||
      (value_length == 0 &&
       napi_create_typedarray(env, napi_uint8_array, 0, values_buffer, 0, &values_array) != napi_ok) ||
      napi_set_named_property(env, result, "values", values_array) != napi_ok) {
    free(ranges);
    free(values);
    return fail(env, "Unable to create TLV8 result arrays");
  }
  if (value_length != 0) {
    for (size_t index = 0; index < value_length; ++index) {
      ((uint8_t *)values_output)[index] = values[index];
    }
  }
  free(ranges);
  free(values);
  return result;
}

napi_status tlv8_register(napi_env env, napi_value exports)
{
  const napi_property_descriptor properties[] = {
      {"encodeTlv8", NULL, encode_tlv8, NULL, NULL, NULL, napi_default, NULL},
      {"decodeTlv8", NULL, decode_tlv8, NULL, NULL, NULL, napi_default, NULL}
  };
  return napi_define_properties(env, exports, sizeof(properties) / sizeof(properties[0]), properties);
}
