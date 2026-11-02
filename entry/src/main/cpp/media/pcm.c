#include "pcm.h"

int pcm_swap_s16(uint8_t *output, const uint8_t *input, size_t length)
{
  if ((length & 1u) != 0 || (length != 0 && (output == NULL || input == NULL))) return 0;
  for (size_t offset = 0; offset < length; offset += 2) {
    const uint8_t low = input[offset];
    const uint8_t high = input[offset + 1];
    output[offset] = high;
    output[offset + 1] = low;
  }
  return 1;
}