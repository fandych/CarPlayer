#include "iap2_link.h"

#define IAP2_HEADER_LENGTH 9u
#define IAP2_MAX_FRAME_LENGTH 65535u

static uint8_t checksum(const uint8_t *bytes, size_t length)
{
  uint8_t sum = 0;
  for (size_t index = 0; index < length; ++index) {
    sum = (uint8_t)(sum + bytes[index]);
  }
  return (uint8_t)(0u - sum);
}

size_t iap2_link_encode(uint8_t *output, size_t capacity, uint8_t control,
                        uint8_t sequence, uint8_t acknowledgement, uint8_t session,
                        const uint8_t *payload, size_t payload_length)
{
  if (output == NULL || (payload_length != 0 && payload == NULL) ||
      payload_length > IAP2_MAX_FRAME_LENGTH - IAP2_HEADER_LENGTH - 1u) {
    return 0;
  }
  const size_t length = IAP2_HEADER_LENGTH + payload_length + (payload_length != 0 ? 1u : 0u);
  if (capacity < length) {
    return 0;
  }
  output[0] = 0xff;
  output[1] = 0x5a;
  output[2] = (uint8_t)(length >> 8);
  output[3] = (uint8_t)length;
  output[4] = control;
  output[5] = sequence;
  output[6] = acknowledgement;
  output[7] = session;
  output[8] = checksum(output, 8);
  if (payload_length != 0) {
    for (size_t index = 0; index < payload_length; ++index) {
      output[IAP2_HEADER_LENGTH + index] = payload[index];
    }
    output[length - 1] = checksum(payload, payload_length);
  }
  return length;
}

iap2_link_scan_result iap2_link_scan(const uint8_t *bytes, size_t length)
{
  iap2_link_scan_result result = {0, 0, 0};
  if (bytes == NULL || length == 0) {
    return result;
  }
  size_t offset = 0;
  while (offset + 1 < length) {
    if (bytes[offset] != 0xff || bytes[offset + 1] != 0x5a) {
      ++offset;
      continue;
    }
    if (length - offset < IAP2_HEADER_LENGTH) {
      result.consumed = offset;
      return result;
    }
    const size_t frame_length = ((size_t)bytes[offset + 2] << 8) | bytes[offset + 3];
    /* A payload-bearing frame needs at least one payload byte plus its checksum. */
    if (frame_length < IAP2_HEADER_LENGTH || frame_length == IAP2_HEADER_LENGTH + 1u ||
        checksum(bytes + offset, IAP2_HEADER_LENGTH) != 0) {
      ++offset;
      continue;
    }
    if (length - offset < frame_length) {
      result.consumed = offset;
      return result;
    }
    if (checksum(bytes + offset + IAP2_HEADER_LENGTH, frame_length - IAP2_HEADER_LENGTH) != 0) {
      ++offset;
      continue;
    }
    result.frame_offset = offset;
    result.frame_length = frame_length;
    result.consumed = offset + frame_length;
    return result;
  }
  /* The final byte may be the first byte of a split sync marker. */
  result.consumed = length - 1;
  return result;
}