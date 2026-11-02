#include "session_core.h"

#include <stdatomic.h>
#include <stddef.h>

static _Atomic uint64_t g_generation = 0;

int session_core_advance(uint64_t *generation)
{
  if (generation == NULL) {
    return 0;
  }
  uint64_t current = atomic_load_explicit(&g_generation, memory_order_relaxed);
  while (current != UINT64_MAX) {
    if (atomic_compare_exchange_weak_explicit(&g_generation, &current, current + 1,
                                              memory_order_acq_rel, memory_order_relaxed)) {
      *generation = current + 1;
      return 1;
    }
  }
  return 0;
}

int session_core_is_current(uint64_t generation)
{
  return generation != 0 &&
      atomic_load_explicit(&g_generation, memory_order_acquire) == generation;
}
