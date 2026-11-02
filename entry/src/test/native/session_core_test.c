#include "../../main/cpp/session/session_core.h"

#include <stddef.h>

int test_session_core(void)
{
  uint64_t first = 0;
  uint64_t second = 0;
  if (session_core_is_current(0)) return 1;
  if (!session_core_advance(&first) || first == 0) return 2;
  if (!session_core_is_current(first)) return 3;
  if (!session_core_advance(&second) || second != first + 1) return 4;
  if (session_core_is_current(first) || !session_core_is_current(second)) return 5;
  if (session_core_advance(NULL)) return 6;
  return 0;
}
