#ifndef CARPLAYER_IAP2_CONTROL_H
#define CARPLAYER_IAP2_CONTROL_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
  size_t consumed;
  size_t frame_offset;
  size_t frame_length;
} iap2_control_scan_result;

/* Destination and body must not overlap. Zero indicates an invalid size or buffer. */
size_t iap2_control_encode(uint8_t *output, size_t capacity, uint16_t message_id,
                           const uint8_t *body, size_t body_length);
size_t iap2_parameter_encode(uint8_t *output, size_t capacity, uint16_t id,
                             const uint8_t *value, size_t value_length);
iap2_control_scan_result iap2_control_scan(const uint8_t *bytes, size_t length);

/* Returns 1 for a parameter, 0 at the end, and -1 for malformed input. */
int iap2_parameter_next(const uint8_t *bytes, size_t length, size_t *offset,
                        uint16_t *id, size_t *value_offset, size_t *value_length);

#ifdef __cplusplus
}
#endif

#endif