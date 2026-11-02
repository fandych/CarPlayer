#ifndef CARPLAYER_IAP2_LINK_H
#define CARPLAYER_IAP2_LINK_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* A scan consumes only bytes that cannot belong to an incomplete frame. */
typedef struct {
  size_t consumed;
  size_t frame_offset;
  size_t frame_length;
} iap2_link_scan_result;

/* Returns the encoded size, or zero when the input or destination is invalid. */
size_t iap2_link_encode(uint8_t *output, size_t capacity, uint8_t control,
                        uint8_t sequence, uint8_t acknowledgement, uint8_t session,
                        const uint8_t *payload, size_t payload_length);

/* Finds one checksum-valid frame, skipping garbage and preserving partial input. */
iap2_link_scan_result iap2_link_scan(const uint8_t *bytes, size_t length);

#ifdef __cplusplus
}
#endif

#endif