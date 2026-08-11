"""
cache_utils.py — Sarathi cache helpers
=======================================
Provides jittered_ttl() to add random noise to cache expiry times.

WHY JITTER?
-----------
When many cache keys share the same TTL they all expire at the same moment,
causing every concurrent request to miss the cache and hit Postgres/OSRM
simultaneously — the "thundering herd" / cache stampede problem.

Adding a small random delta spreads the expiry times so misses are staggered.
"""
import random


def jittered_ttl(base_seconds: int, max_jitter_seconds: int = 60) -> int:
    """
    Return base_seconds ± a random delta in [0, max_jitter_seconds].

    The sign of the jitter is itself random, so the result is in:
        [base_seconds - max_jitter_seconds, base_seconds + max_jitter_seconds]

    Always returns at least 1 second so cache entries are never set
    with a zero or negative TTL.

    Examples
    --------
    jittered_ttl(300)       → somewhere in [240, 360]   (±60 s default)
    jittered_ttl(60, 30)    → somewhere in [30,  90]    (±30 s)
    jittered_ttl(30, 10)    → somewhere in [20,  40]    (±10 s)
    jittered_ttl(43200, 300)→ somewhere in [42900, 43500] (±5 min, for sessions)
    """
    jitter = random.randint(0, max_jitter_seconds) * random.choice([-1, 1])
    return max(1, base_seconds + jitter)
