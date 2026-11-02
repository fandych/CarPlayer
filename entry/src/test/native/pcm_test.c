#include "../../main/cpp/media/pcm.h"

int test_pcm(void)
{
  const uint8_t input[] = {0x34, 0x12, 0xfe, 0xff, 0, 0x80};
  uint8_t output[sizeof(input)] = {0};
  const uint8_t expected[] = {0x12, 0x34, 0xff, 0xfe, 0x80, 0};
  if (!pcm_swap_s16(output, input, sizeof(input))) return 1;
  for (size_t index = 0; index < sizeof(input); ++index) {
    if (output[index] != expected[index]) return 2;
  }
  if (!pcm_swap_s16(output, output, sizeof(output))) return 3;
  for (size_t index = 0; index < sizeof(input); ++index) {
    if (output[index] != input[index]) return 4;
  }
  if (pcm_swap_s16(output, input, 3) || pcm_swap_s16(NULL, input, 2)) return 5;
  if (!pcm_swap_s16(NULL, NULL, 0)) return 6;
  return 0;
}