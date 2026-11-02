#include "../../main/cpp/protocol/iap2_link.h"

static uint8_t large_payload[65526];
static uint8_t large_frame[65536];

int test_iap2_link(void)
{
  uint8_t buffer[64] = {0};
  const uint8_t payload[] = {0x40, 0x40, 0x00, 0x06, 0xaa, 0x01};
  const uint8_t expected[] = {0xff, 0x5a, 0x00, 0x10, 0x40, 0x0b, 0x00, 0x01,
                              0x4b, 0x40, 0x40, 0x00, 0x06, 0xaa, 0x01, 0xcf};
  const size_t length = iap2_link_encode(buffer, sizeof(buffer), 0x40, 11, 0, 1,
                                         payload, sizeof(payload));
  if (length != sizeof(expected)) return 1;
  for (size_t index = 0; index < length; ++index) {
    if (buffer[index] != expected[index]) return 2;
  }
  for (size_t split = 1; split < length; ++split) {
    const iap2_link_scan_result partial = iap2_link_scan(buffer, split);
    if (partial.frame_length != 0 || partial.consumed != 0) return 3;
  }
  iap2_link_scan_result scan = iap2_link_scan(buffer, length);
  if (scan.frame_offset != 0 || scan.frame_length != length || scan.consumed != length) return 4;
  buffer[9] ^= 1;
  scan = iap2_link_scan(buffer, length);
  if (scan.frame_length != 0 || scan.consumed != length - 1) return 5;
  buffer[9] ^= 1;
  buffer[length] = 0xff;
  buffer[length + 1] = 0x5a;
  scan = iap2_link_scan(buffer, length + 2);
  if (scan.frame_length != length || scan.consumed != length) return 6;
  if (iap2_link_encode(buffer, 8, 0x40, 0, 0, 0, NULL, 0) != 0) return 7;
  if (iap2_link_encode(buffer, sizeof(buffer), 0x40, 0, 0, 0, NULL, 1) != 0) return 8;
  if (iap2_link_encode(buffer, sizeof(buffer), 0x40, 12, 9, 0, NULL, 0) != 9) return 9;
  scan = iap2_link_scan(buffer, 9);
  if (scan.frame_length != 9 || scan.consumed != 9) return 10;
  {
    uint8_t empty_payload[10];
    uint8_t sum = 0;
    empty_payload[0] = 0xff;
    empty_payload[1] = 0x5a;
    empty_payload[2] = 0x00;
    empty_payload[3] = 0x0a;
    empty_payload[4] = 0x40;
    empty_payload[5] = 0x01;
    empty_payload[6] = 0x00;
    empty_payload[7] = 0x0a;
    for (size_t index = 0; index < 8; ++index) sum = (uint8_t)(sum + empty_payload[index]);
    empty_payload[8] = (uint8_t)(0u - sum);
    empty_payload[9] = 0x00;
    scan = iap2_link_scan(empty_payload, sizeof(empty_payload));
    if (scan.frame_length != 0) return 16;
  }
  for (size_t size = 1; size <= 256; ++size) {
    for (size_t index = 0; index < size; ++index) large_payload[index] = (uint8_t)(index * 37u + size);
    const size_t encoded = iap2_link_encode(large_frame, sizeof(large_frame), 0x40,
                                             (uint8_t)size, 0xff, 1, large_payload, size);
    if (encoded != size + 10) return 11;
    scan = iap2_link_scan(large_frame, encoded);
    if (scan.frame_length != encoded || scan.consumed != encoded) return 12;
    for (size_t index = 0; index < size; ++index) {
      if (large_frame[index + 9] != large_payload[index]) return 13;
    }
  }
  if (iap2_link_encode(large_frame, sizeof(large_frame), 0x40, 0, 0, 0, large_payload, 65525) != 65535) return 14;
  if (iap2_link_encode(large_frame, sizeof(large_frame), 0x40, 0, 0, 0, large_payload, 65526) != 0) return 15;
  return 0;
}