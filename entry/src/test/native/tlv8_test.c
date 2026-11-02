#include "../../main/cpp/protocol/tlv8.h"

int test_tlv8(void)
{
  uint8_t long_value[256];
  for (size_t index = 0; index < sizeof(long_value); ++index) {
    long_value[index] = (uint8_t)index;
  }
  const uint8_t first[] = {0x31};
  const uint8_t repeated[] = {0x42};
  const uint8_t *values[] = {first, long_value, repeated, NULL};
  const size_t lengths[] = {sizeof(first), sizeof(long_value), sizeof(repeated), 0};
  const uint8_t types[] = {7, 8, 8, 9};
  const size_t encoded_size = tlv8_encoded_size(types, values, lengths, 4);
  if (encoded_size != 270) return 1;

  uint8_t encoded[270];
  if (tlv8_encode(encoded, sizeof(encoded), types, values, lengths, 4) != sizeof(encoded)) return 2;
  if (encoded[0] != 7 || encoded[1] != 1 || encoded[2] != 0x31) return 3;
  if (encoded[3] != 8 || encoded[4] != 255 || encoded[5] != 0) return 4;
  if (encoded[260] != 8 || encoded[261] != 1 || encoded[262] != 255) return 5;
  if (encoded[263] != 0xff || encoded[264] != 0) return 6;
  if (encoded[265] != 8 || encoded[266] != 1 || encoded[267] != 0x42) return 7;
  if (encoded[268] != 9 || encoded[269] != 0) return 8;

  tlv8_range ranges[6];
  size_t count = 0;
  if (!tlv8_parse(encoded, sizeof(encoded), ranges, 6, &count) || count != 6) return 9;
  if (ranges[0].type != 7 || ranges[0].value_offset != 2 || ranges[0].value_length != 1) return 10;
  if (ranges[1].type != 8 || ranges[1].value_offset != 5 || ranges[1].value_length != 255) return 11;
  if (ranges[2].type != 8 || ranges[2].value_offset != 262 || ranges[2].value_length != 1) return 12;
  if (ranges[3].type != 0xff || ranges[3].value_length != 0) return 13;
  if (ranges[4].type != 8 || ranges[4].value_offset != 267 || ranges[4].value_length != 1) return 14;
  if (ranges[5].type != 9 || ranges[5].value_offset != 270 || ranges[5].value_length != 0) return 15;

  tlv8_range decoded_items[3];
  uint8_t decoded_values[258];
  size_t decoded_count = 0;
  size_t decoded_length = 0;
  if (!tlv8_decode(encoded, sizeof(encoded), decoded_items, 3, decoded_values,
                   sizeof(decoded_values), &decoded_count, &decoded_length) ||
      decoded_count != 3 || decoded_length != sizeof(decoded_values)) return 16;
  if (decoded_items[0].type != 7 || decoded_items[0].value_offset != 0 ||
      decoded_items[0].value_length != 1 || decoded_values[0] != 0x31) return 17;
  if (decoded_items[1].type != 8 || decoded_items[1].value_offset != 257 ||
      decoded_items[1].value_length != 1 || decoded_values[257] != 0x42) return 18;
  if (decoded_items[2].type != 9 || decoded_items[2].value_offset != 258 ||
      decoded_items[2].value_length != 0) return 19;

  const uint8_t truncated[] = {1};
  const uint8_t invalid_separator[] = {0xff, 1, 0};
  if (tlv8_parse(truncated, sizeof(truncated), NULL, 0, &count)) return 20;
  if (tlv8_parse(invalid_separator, sizeof(invalid_separator), NULL, 0, &count)) return 21;
  if (tlv8_parse(encoded, sizeof(encoded), ranges, 5, &count)) return 22;
  if (tlv8_decode(encoded, sizeof(encoded), decoded_items, 2, decoded_values,
                  sizeof(decoded_values), &decoded_count, &decoded_length)) return 23;

  const uint8_t invalid_type[] = {0xff};
  const uint8_t *invalid_values[] = {first};
  const size_t invalid_lengths[] = {sizeof(first)};
  if (tlv8_encoded_size(invalid_type, invalid_values, invalid_lengths, 1) != (size_t)-1) return 24;
  if (tlv8_encode(encoded, sizeof(encoded) - 1, types, values, lengths, 4) != 0) return 25;
  return 0;
}
