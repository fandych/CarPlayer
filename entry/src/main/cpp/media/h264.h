#ifndef CARPLAYER_H264_H
#define CARPLAYER_H264_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Returns the NAL count. Each output pair is an offset and length into the input. */
size_t h264_split_units(const uint8_t *input, size_t length, uint32_t *pairs, size_t capacity);

#ifdef __cplusplus
}
#endif

#endif