#!/usr/bin/env python3
"""Hashed stream keys for the lab pilot: one canonical key per (game, purpose, owner, arm).

A key is a flat JSON object of strings; its canonical bytes are hashed with sha256 and the first
eight bytes become a 63-bit seed in 1..2**63-1. `issue` hands out seeds for a whole key list in
sorted canonical order and re-keys (attempt "1", "2", ...) on a collision, so a run is reproducible.
"""
import hashlib
import json

FIELDS = ("namespace", "split", "part", "cell", "source", "purpose", "replicate", "owner", "arm", "attempt")


class IntegrityError(Exception):
    """Two different keys (or a key and a forbidden digest) share a full sha256 digest."""


def _text(name, value):
    if isinstance(value, bool) or value is None or isinstance(value, float):
        raise TypeError("key field %r must be a str or int, got %r" % (name, value))
    if isinstance(value, int):
        return str(value)
    if isinstance(value, str):
        return value
    raise TypeError("key field %r must be a str or int, got %r" % (name, value))


def key(namespace, split, part, cell, source, purpose, replicate, owner="", arm="", attempt=""):
    """The key as a dict of strings; ints become decimal strings, float/None are refused."""
    vals = dict(namespace=namespace, split=split, part=part, cell=cell, source=source, purpose=purpose,
                replicate=replicate, owner=owner, arm=arm, attempt=attempt)
    return {n: _text(n, vals[n]) for n in FIELDS}


def canonical(k):
    return json.dumps(k, sort_keys=True, separators=(",", ":"), ensure_ascii=True, allow_nan=False).encode("ascii")


def digest(k):
    return hashlib.sha256(canonical(k)).digest()


def seed_of(dig):
    return 1 + int.from_bytes(dig[:8], "big") % (2 ** 63 - 1)


def issue(keys, forbidden_seeds=(), forbidden_digests=()):
    """Return (issued, attempts): issued = [{key, seed, digest}] in sorted canonical order,
    attempts = [{key, attempt, reason}] for every retry. Seeds are ints; digests are hex."""
    bad_seeds = {int(s) for s in forbidden_seeds}
    bad_digests = {d.hex() if isinstance(d, bytes) else str(d) for d in forbidden_digests}
    pending = sorted((canonical(key(**k)), key(**k)) for k in keys)
    by_seed, by_digest, issued, attempts = {}, {}, [], []
    for _, base in pending:
        n = 0
        while True:
            k = dict(base, attempt="" if n == 0 else str(n))
            dig = digest(k)
            seed = seed_of(dig)
            if dig.hex() in bad_digests or by_digest.get(dig.hex(), k) != k:
                raise IntegrityError("full digest collision for %s" % canonical(k).decode())
            reason = "forbidden_seed" if seed in bad_seeds else "seed_collision" if seed in by_seed else None
            if reason is None:
                break
            attempts.append({"key": k, "attempt": str(n + 1), "reason": reason})
            n += 1
        by_seed[seed], by_digest[dig.hex()] = k, k
        issued.append({"key": k, "seed": seed, "digest": dig.hex()})
    return issued, attempts
