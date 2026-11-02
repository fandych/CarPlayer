#include "iap2_control.h"

#define IAP2_CONTROL_HEADER 6u
#define IAP2_PARAMETER_HEADER 4u
#define IAP2_MAX_SIZE 65535u

static size_t read_u16(const uint8_t *bytes)
{
  return ((size_t)bytes[0] << 8) | bytes[1];
}

static void write_u16(uint8_t *bytes, size_t value)
{
  bytes[0] = (uint8_t)(value >> 8);
  bytes[1] = (uint8_t)value;
}

static size_t encode(uint8_t *output, size_t capacity, size_t header, uint16_t id,
                     const uint8_t *data, size_t data_length)
{
  if (output == NULL || (data_length != 0 && data == NULL) ||
      data_length > IAP2_MAX_SIZE - header || capacity < header + data_length) {
    return 0;
  }
  const size_t length = header + data_length;
  if (header == IAP2_CONTROL_HEADER) {
    output[0] = 0x40;
    output[1] = 0x40;
    write_u16(output + 2, length);
    write_u16(output + 4, id);
  } else {
    write_u16(output, length);
    write_u16(output + 2, id);
  }
  for (size_t index = 0; index < data_length; ++index) {
    output[header + index] = data[index];
  }
  return length;
}

size_t iap2_control_encode(uint8_t *output, size_t capacity, uint16_t message_id,
                           const uint8_t *body, size_t body_length)
{
  return encode(output, capacity, IAP2_CONTROL_HEADER, message_id, body, body_length);
}

size_t iap2_parameter_encode(uint8_t *output, size_t capacity, uint16_t id,
                             const uint8_t *value, size_t value_length)
{
  return encode(output, capacity, IAP2_PARAMETER_HEADER, id, value, value_length);
}

iap2_control_scan_result iap2_control_scan(const uint8_t *bytes, size_t length)
{
  iap2_control_scan_result result = {0, 0, 0};
  if (bytes == NULL || length == 0) return result;
  size_t offset = 0;
  while (offset + 1 < length) {
    if (bytes[offset] != 0x40 || bytes[offset + 1] != 0x40) {
      ++offset;
      continue;
    }
    if (length - offset < IAP2_CONTROL_HEADER) {
      result.consumed = offset;
      return result;
    }
    const size_t frame_length = read_u16(bytes + offset + 2);
    if (frame_length < IAP2_CONTROL_HEADER) {
      ++offset;
      continue;
    }
    if (length - offset < frame_length) {
      result.consumed = offset;
      return result;
    }
    result.frame_offset = offset;
    result.frame_length = frame_length;
    result.consumed = offset + frame_length;
    return result;
  }
  result.consumed = length - 1;
  return result;
}

int iap2_parameter_next(const uint8_t *bytes, size_t length, size_t *offset,
                        uint16_t *id, size_t *value_offset, size_t *value_length)
{
  if (offset == NULL || id == NULL || value_offset == NULL || value_length == NULL ||
      *offset > length || (length != 0 && bytes == NULL)) return -1;
  if (*offset == length) return 0;
  if (length - *offset < IAP2_PARAMETER_HEADER) return -1;
  const size_t parameter_length = read_u16(bytes + *offset);
  if (parameter_length < IAP2_PARAMETER_HEADER || parameter_length > length - *offset) return -1;
  *id = (uint16_t)read_u16(bytes + *offset + 2);
  *value_offset = *offset + IAP2_PARAMETER_HEADER;
  *value_length = parameter_length - IAP2_PARAMETER_HEADER;
  *offset += parameter_length;
  return 1;
}