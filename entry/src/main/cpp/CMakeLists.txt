cmake_minimum_required(VERSION 3.5)
project(carplay_projection)

add_library(projection SHARED
  projection_napi.cpp
  projection_helpers.cpp
  projection_encoder_events.cpp
  projection_screen_capture.cpp
  projection_video_encoder.cpp
)
target_link_libraries(projection PUBLIC
  libace_napi.z.so
  libnative_media_venc.so
  libnative_media_codecbase.so
  libnative_media_core.so
  libnative_avscreen_capture.so
  libnative_window.so
)
