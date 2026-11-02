#ifndef CARPLAYER_TLV8_H
#define CARPLAYER_TLV8_H

#include <stddef.h>
#include <stdint.h>

typedef struct {
  uint8_t type;
  size_t value_offset;
  size_t value_length;
} tlv8_range;

int tlv8_parse(const uint8_t *input, size_t length, tlv8_range *ranges,
               size_t capacity, size_t *count);
int tlv8_decode(const uint8_t *input, size_t length, tlv8_range *items,
                size_t item_capacity, uint8_t *values, size_t value_capacity,
                size_t *item_count, size_t *value_length);
size_t tlv8_encoded_size(const uint8_t *types, const uint8_t *const values[],
                         const size_t *lengths, size_t count);
size_t tlv8_encode(uint8_t *output, size_t capacity, const uint8_t *types,
                   const uint8_t *const values[], const size_t *lengths, size_t count);

#endif
