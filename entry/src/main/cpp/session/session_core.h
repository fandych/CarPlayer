#ifndef CARPLAYER_SESSION_CORE_H
#define CARPLAYER_SESSION_CORE_H

#include <stdint.h>

int session_core_advance(uint64_t *generation);
int session_core_is_current(uint64_t generation);

#endif
