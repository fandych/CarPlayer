#include "projection_internal.h"

napi_value Init(napi_env env, napi_value exports) {
  const napi_property_descriptor properties[] = {
      {"isVideoEncoderSizeSupported", nullptr, IsVideoEncoderSizeSupported, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"createVideoEncoder", nullptr, CreateVideoEncoder, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"stopVideoEncoder", nullptr, StopVideoEncoder, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"requestKeyFrame", nullptr, RequestKeyFrame, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"startScreenCapture", nullptr, StartScreenCapture, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"stopScreenCapture", nullptr, StopScreenCapture, nullptr, nullptr, nullptr, napi_default, nullptr}
  };
  napi_define_properties(env, exports, sizeof(properties) / sizeof(properties[0]), properties);
  return exports;
}

NAPI_MODULE(projection, Init)
