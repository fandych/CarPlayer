#include "../../main/cpp/media/h264.h"

int test_h264(void)
{
  uint32_t pairs[8] = {0};
  const uint8_t annex[] = {0, 0, 0, 1, 0x67, 1, 0, 0, 1, 0x68, 2};
  if (h264_split_units(annex, sizeof(annex), pairs, 4) != 2 ||
      pairs[0] != 4 || pairs[1] != 2 || pairs[2] != 9 || pairs[3] != 2) return 1;
  const uint8_t config[] = {1, 0x64, 0, 0x28, 0xff, 0xe1, 0, 2, 0x67, 1, 1, 0, 2, 0x68, 2};
  if (h264_split_units(config, sizeof(config), pairs, 4) != 2 ||
      pairs[0] != 8 || pairs[1] != 2 || pairs[2] != 13 || pairs[3] != 2) return 2;
  const uint8_t lengths[] = {0, 0, 0, 2, 0x65, 1, 0, 0, 0, 2, 0x06, 2};
  if (h264_split_units(lengths, sizeof(lengths), pairs, 4) != 2 ||
      pairs[0] != 4 || pairs[1] != 2 || pairs[2] != 10 || pairs[3] != 2) return 3;
  const uint8_t invalid[] = {0, 0, 0, 5, 0x65};
  if (h264_split_units(invalid, sizeof(invalid), pairs, 4) != 1 || pairs[0] != 0 || pairs[1] != 5) return 4;
  if (h264_split_units(NULL, 0, pairs, 4) != 0) return 5;
  if (h264_split_units(annex, sizeof(annex), NULL, 0) != 2) return 6;
  return 0;
}