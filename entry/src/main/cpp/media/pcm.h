#ifndef CARPLAYER_PCM_H
#define CARPLAYER_PCM_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Swaps 16-bit samples; input and output may be identical, but not partially overlap. */
int pcm_swap_s16(uint8_t *output, const uint8_t *input, size_t length);

#ifdef __cplusplus
}
#endif

#endif