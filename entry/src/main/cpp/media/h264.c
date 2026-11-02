#include "h264.h"

static void add_unit(uint32_t *pairs, size_t capacity, size_t *count, size_t start, size_t length)
{
  if (*count < capacity && pairs != NULL) {
    pairs[*count * 2] = (uint32_t)start;
    pairs[*count * 2 + 1] = (uint32_t)length;
  }
  ++*count;
}

static size_t split_annex_b(const uint8_t *input, size_t length, uint32_t *pairs, size_t capacity)
{
  size_t count = 0, index = 0, body_start = 0;
  int found = 0;
  while (length - index > 3) {
    size_t prefix = 0;
    if (input[index] == 0 && input[index + 1] == 0) {
      if (input[index + 2] == 1) prefix = 3;
      else if (input[index + 2] == 0 && input[index + 3] == 1) prefix = 4;
    }
    if (prefix == 0) {
      ++index;
      continue;
    }
    if (found && index > body_start) add_unit(pairs, capacity, &count, body_start, index - body_start);
    found = 1;
    body_start = index + prefix;
    index = body_start;
  }
  if (found && length > body_start) add_unit(pairs, capacity, &count, body_start, length - body_start);
  return count;
}

static size_t split_configuration(const uint8_t *input, size_t length, uint32_t *pairs, size_t capacity)
{
  if (length < 7 || input[0] != 1) return 0;
  size_t offset = 6, count = 0;
  for (size_t group = 0; group < 2; ++group) {
    size_t units;
    if (group == 0) units = input[5] & 0x1f;
    else {
      if (offset >= length) return 0;
      units = input[offset++];
    }
    for (size_t index = 0; index < units; ++index) {
      if (length - offset < 2) return 0;
      const size_t size = ((size_t)input[offset] << 8) | input[offset + 1];
      offset += 2;
      if (size == 0 || size > length - offset) return 0;
      add_unit(pairs, capacity, &count, offset, size);
      offset += size;
    }
  }
  return offset == length ? count : 0;
}

static size_t split_lengths(const uint8_t *input, size_t length, uint32_t *pairs, size_t capacity)
{
  size_t offset = 0, count = 0;
  while (length - offset >= 4) {
    const uint32_t size = ((uint32_t)input[offset] << 24) | ((uint32_t)input[offset + 1] << 16) |
                          ((uint32_t)input[offset + 2] << 8) | input[offset + 3];
    offset += 4;
    if (size == 0 || size > length - offset) return 0;
    add_unit(pairs, capacity, &count, offset, size);
    offset += size;
  }
  return offset == length ? count : 0;
}

size_t h264_split_units(const uint8_t *input, size_t length, uint32_t *pairs, size_t capacity)
{
  if (input == NULL || length == 0 || length > UINT32_MAX) return 0;
  size_t count = split_annex_b(input, length, pairs, capacity);
  if (count != 0) return count;
  count = split_configuration(input, length, pairs, capacity);
  if (count != 0) return count;
  count = split_lengths(input, length, pairs, capacity);
  if (count != 0) return count;
  count = 0;
  add_unit(pairs, capacity, &count, 0, length);
  return count;
}