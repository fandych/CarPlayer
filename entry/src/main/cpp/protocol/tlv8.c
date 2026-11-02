#include "tlv8.h"

#define TLV8_SEPARATOR 0xffu
#define TLV8_MAX_FRAGMENT 255u
#define TLV8_MAX_BYTES (1024u * 1024u)

static size_t invalid_size(void)
{
  return (size_t)-1;
}

int tlv8_parse(const uint8_t *input, size_t length, tlv8_range *ranges,
               size_t capacity, size_t *count)
{
  if (count == NULL || (length != 0 && input == NULL) || length > TLV8_MAX_BYTES) {
    return 0;
  }
  size_t offset = 0;
  size_t items = 0;
  while (offset < length) {
    if (length - offset < 2) {
      return 0;
    }
    const uint8_t type = input[offset];
    const size_t value_length = input[offset + 1];
    const size_t value_offset = offset + 2;
    if (value_length > length - value_offset || (type == TLV8_SEPARATOR && value_length != 0)) {
      return 0;
    }
    if (ranges != NULL) {
      if (items >= capacity) {
        return 0;
      }
      ranges[items].type = type;
      ranges[items].value_offset = value_offset;
      ranges[items].value_length = value_length;
    }
    ++items;
    offset = value_offset + value_length;
  }
  *count = items;
  return 1;
}

int tlv8_decode(const uint8_t *input, size_t length, tlv8_range *items,
                size_t item_capacity, uint8_t *values, size_t value_capacity,
                size_t *item_count, size_t *value_length)
{
  if (item_count == NULL || value_length == NULL ||
      (length != 0 && input == NULL) || length > TLV8_MAX_BYTES) {
    return 0;
  }
  int item_for_type[TLV8_SEPARATOR];
  for (size_t index = 0; index < TLV8_SEPARATOR; ++index) {
    item_for_type[index] = -1;
  }
  size_t offset = 0;
  size_t item_total = 0;
  size_t value_total = 0;
  int previous_type = -1;
  size_t previous_length = 0;
  int separator_seen = 0;
  while (offset < length) {
    if (length - offset < 2) {
      return 0;
    }
    const uint8_t type = input[offset];
    const size_t current_length = input[offset + 1];
    const size_t current_offset = offset + 2;
    if (current_length > length - current_offset ||
        (type == TLV8_SEPARATOR && current_length != 0)) {
      return 0;
    }
    if (type == TLV8_SEPARATOR) {
      previous_type = -1;
      previous_length = 0;
      separator_seen = 1;
      offset = current_offset;
      continue;
    }

    const int continuation = previous_type == (int)type &&
        previous_length == TLV8_MAX_FRAGMENT && !separator_seen;
    size_t item_index = 0;
    if (continuation) {
      item_index = (size_t)item_for_type[type];
      if (items != NULL) {
        items[item_index].value_length += current_length;
      }
    } else {
      int mapped_index = item_for_type[type];
      if (mapped_index < 0) {
        if (item_total >= item_capacity && items != NULL) {
          return 0;
        }
        item_index = item_total++;
        item_for_type[type] = (int)item_index;
        if (items != NULL) {
          items[item_index].type = type;
        }
      } else {
        item_index = (size_t)mapped_index;
      }
      if (items != NULL) {
        items[item_index].value_offset = value_total;
        items[item_index].value_length = current_length;
      }
    }
    if (current_length > TLV8_MAX_BYTES - value_total ||
        (values != NULL && current_length > value_capacity - value_total)) {
      return 0;
    }
    if (current_length != 0 && values != NULL) {
      for (size_t byte = 0; byte < current_length; ++byte) {
        values[value_total + byte] = input[current_offset + byte];
      }
    }
    value_total += current_length;
    previous_type = (int)type;
    previous_length = current_length;
    separator_seen = 0;
    offset = current_offset + current_length;
  }
  *item_count = item_total;
  *value_length = value_total;
  return 1;
}

size_t tlv8_encoded_size(const uint8_t *types, const uint8_t *const values[],
                         const size_t *lengths, size_t count)
{
  if (count != 0 && (types == NULL || values == NULL || lengths == NULL)) {
    return invalid_size();
  }
  size_t total = 0;
  for (size_t index = 0; index < count; ++index) {
    if (types[index] == TLV8_SEPARATOR || (lengths[index] != 0 && values[index] == NULL)) {
      return invalid_size();
    }
    if (index != 0 && types[index] == types[index - 1]) {
      if (total > TLV8_MAX_BYTES - 2u) {
        return invalid_size();
      }
      total += 2u;
    }
    const size_t fragments = lengths[index] == 0 ? 1u : (lengths[index] - 1u) / TLV8_MAX_FRAGMENT + 1u;
    if (fragments > (TLV8_MAX_BYTES - total) / 2u ||
        lengths[index] > TLV8_MAX_BYTES - total - fragments * 2u) {
      return invalid_size();
    }
    total += fragments * 2u + lengths[index];
  }
  return total;
}

size_t tlv8_encode(uint8_t *output, size_t capacity, const uint8_t *types,
                   const uint8_t *const values[], const size_t *lengths, size_t count)
{
  const size_t required = tlv8_encoded_size(types, values, lengths, count);
  if (required == invalid_size() || required > capacity || (required != 0 && output == NULL)) {
    return 0;
  }
  size_t offset = 0;
  for (size_t index = 0; index < count; ++index) {
    if (index != 0 && types[index] == types[index - 1]) {
      output[offset++] = TLV8_SEPARATOR;
      output[offset++] = 0;
    }
    if (lengths[index] == 0) {
      output[offset++] = types[index];
      output[offset++] = 0;
      continue;
    }
    size_t value_offset = 0;
    while (value_offset < lengths[index]) {
      size_t fragment_length = lengths[index] - value_offset;
      if (fragment_length > TLV8_MAX_FRAGMENT) {
        fragment_length = TLV8_MAX_FRAGMENT;
      }
      output[offset++] = types[index];
      output[offset++] = (uint8_t)fragment_length;
      for (size_t byte = 0; byte < fragment_length; ++byte) {
        output[offset++] = values[index][value_offset + byte];
      }
      value_offset += fragment_length;
    }
  }
  return offset;
}
