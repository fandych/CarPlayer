cmake_minimum_required(VERSION 3.5)
project(carplay_projection)

add_library(projection SHARED projection_napi.cpp)
add_library(iap2codec SHARED
  protocol/iap2_link.c
  protocol/iap2_link_napi.c
  protocol/iap2_control.c
  protocol/iap2_control_napi.c
  protocol/tlv8.c
  protocol/tlv8_napi.c
)

target_link_libraries(iap2codec PUBLIC libace_napi.z.so)
add_library(mediabytes SHARED media/pcm.c media/pcm_napi.c media/h264.c media/h264_napi.c)
target_link_libraries(mediabytes PUBLIC libace_napi.z.so)
add_library(sessioncore SHARED session/session_core.c session/session_core_napi.c)
target_link_libraries(sessioncore PUBLIC libace_napi.z.so)

target_link_libraries(projection PUBLIC
  libace_napi.z.so
  libnative_media_venc.so
  libnative_media_codecbase.so
  libnative_media_core.so
  libnative_avscreen_capture.so
  libnative_window.so
)
