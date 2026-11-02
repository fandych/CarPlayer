#include "session_core.h"

#include <napi/native_api.h>
#include <stdint.h>

static napi_value fail(napi_env env, const char *message)
{
  napi_throw_error(env, NULL, message);
  return NULL;
}

static napi_value create_generation(napi_env env, uint64_t generation)
{
  char decimal[20];
  size_t offset = sizeof(decimal);
  do {
    decimal[--offset] = (char)('0' + generation % 10u);
    generation /= 10u;
  } while (generation != 0);
  napi_value result;
  if (napi_create_string_utf8(env, decimal + offset, sizeof(decimal) - offset, &result) != napi_ok) {
    return fail(env, "Unable to create native session generation token");
  }
  return result;
}

static int parse_generation(napi_env env, napi_value value, uint64_t *generation)
{
  napi_valuetype type;
  if (generation == NULL || napi_typeof(env, value, &type) != napi_ok || type != napi_string) {
    return 0;
  }
  char decimal[21];
  size_t length = 0;
  if (napi_get_value_string_utf8(env, value, decimal, sizeof(decimal), &length) != napi_ok ||
      length == 0 || length >= sizeof(decimal)) {
    return 0;
  }
  uint64_t result = 0;
  for (size_t index = 0; index < length; ++index) {
    if (decimal[index] < '0' || decimal[index] > '9') {
      return 0;
    }
    const uint64_t digit = (uint64_t)(decimal[index] - '0');
    if (result > (UINT64_MAX - digit) / 10u) {
      return 0;
    }
    result = result * 10u + digit;
  }
  if (result == 0) {
    return 0;
  }
  *generation = result;
  return 1;
}

static napi_value advance_generation(napi_env env, napi_callback_info info)
{
  size_t argc = 0;
  uint64_t generation = 0;
  if (napi_get_cb_info(env, info, &argc, NULL, NULL, NULL) != napi_ok || argc != 0 ||
      !session_core_advance(&generation)) {
    return fail(env, "Unable to advance native session generation");
  }
  return create_generation(env, generation);
}

static napi_value is_current_generation(napi_env env, napi_callback_info info)
{
  size_t argc = 1;
  napi_value args[1];
  uint64_t generation = 0;
  if (napi_get_cb_info(env, info, &argc, args, NULL, NULL) != napi_ok ||
      argc != 1 || !parse_generation(env, args[0], &generation)) {
    return fail(env, "Invalid native session generation token");
  }
  napi_value result;
  if (napi_get_boolean(env, session_core_is_current(generation) != 0, &result) != napi_ok) {
    return fail(env, "Unable to create native session generation result");
  }
  return result;
}

static napi_value init(napi_env env, napi_value exports)
{
  const napi_property_descriptor properties[] = {
      {"advanceGeneration", NULL, advance_generation, NULL, NULL, NULL, napi_default, NULL},
      {"isCurrentGeneration", NULL, is_current_generation, NULL, NULL, NULL, napi_default, NULL}
  };
  if (napi_define_properties(env, exports, sizeof(properties) / sizeof(properties[0]), properties) != napi_ok) {
    return NULL;
  }
  return exports;
}

NAPI_MODULE(sessioncore, init)
