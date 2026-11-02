#include "../../main/cpp/protocol/iap2_control.h"

int test_iap2_control(void)
{
  uint8_t buffer[32] = {0};
  const uint8_t body[] = {0x12, 0x34};
  const size_t length = iap2_control_encode(buffer, sizeof(buffer), 0xaa01, body, sizeof(body));
  const uint8_t expected[] = {0x40, 0x40, 0, 8, 0xaa, 1, 0x12, 0x34};
  if (length != sizeof(expected)) return 1;
  for (size_t index = 0; index < length; ++index) {
    if (buffer[index] != expected[index]) return 2;
  }
  for (size_t split = 1; split < length; ++split) {
    const iap2_control_scan_result partial = iap2_control_scan(buffer, split);
    if (partial.frame_length != 0 || partial.consumed != 0) return 3;
  }
  iap2_control_scan_result frame = iap2_control_scan(buffer, length);
  if (frame.frame_length != length || frame.consumed != length) return 4;
  if (iap2_parameter_encode(buffer, sizeof(buffer), 0xabcd, body, sizeof(body)) != 6) return 5;
  size_t offset = 0, value_offset = 0, value_length = 0;
  uint16_t id = 0;
  if (iap2_parameter_next(buffer, 6, &offset, &id, &value_offset, &value_length) != 1 ||
      id != 0xabcd || value_offset != 4 || value_length != 2 || offset != 6) return 6;
  if (iap2_parameter_next(buffer, 6, &offset, &id, &value_offset, &value_length) != 0) return 7;
  offset = 0;
  if (iap2_parameter_next(buffer, 5, &offset, &id, &value_offset, &value_length) != -1) return 8;
  buffer[1] = 3;
  if (iap2_parameter_next(buffer, 6, &offset, &id, &value_offset, &value_length) != -1) return 9;
  if (iap2_control_encode(buffer, sizeof(buffer), 1, body, 65530) != 0) return 10;
  if (iap2_parameter_encode(buffer, sizeof(buffer), 1, NULL, 1) != 0) return 11;
  if (iap2_parameter_encode(buffer, sizeof(buffer), 1, body, 65532) != 0) return 12;
  return 0;
}