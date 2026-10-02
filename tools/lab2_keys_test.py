#!/usr/bin/env python3
"""Tests for tools/lab2_keys.py. Run: python3 -m pytest -q tools/lab2_keys_test.py"""
import importlib.util
import os
import sys

import pytest

_HERE = os.path.dirname(os.path.abspath(__file__))
_SPEC = importlib.util.spec_from_file_location("lab2_keys", os.path.join(_HERE, "lab2_keys.py"))
lk = importlib.util.module_from_spec(_SPEC)
sys.modules["lab2_keys"] = lk
_SPEC.loader.exec_module(lk)

BASE = dict(namespace="ns", split="D", part="A", cell=3, source=7, purpose="terrain", replicate=0)
# Hand-written once, independently of the module (sha256sum of the string below).
CANON = ('{"arm":"","attempt":"","cell":"3","namespace":"ns","owner":"","part":"A","purpose":"terrain",'
         '"replicate":"0","source":"7","split":"D"}')
DIGEST = "82072cd047c81acb3963ec13ee141906a4c04ec8451f6042b34acd7e30616936"
SEED = 146134785981946573


def test_fixed_key_canonical_digest_seed():
    k = lk.key(**BASE)
    assert lk.canonical(k).decode() == CANON
    assert lk.digest(k).hex() == DIGEST
    assert lk.seed_of(lk.digest(k)) == SEED


@pytest.mark.parametrize("bad", [1.5, None, True])
def test_non_text_field_refused_naming_it(bad):
    with pytest.raises(TypeError, match="replicate"):
        lk.key(**dict(BASE, replicate=bad))


def test_forbidden_seed_retries_with_attempt_one():
    issued, attempts = lk.issue([BASE], forbidden_seeds=[SEED])
    assert [(a["attempt"], a["reason"]) for a in attempts] == [("1", "forbidden_seed")]
    assert issued[0]["key"]["attempt"] == "1" and issued[0]["seed"] != SEED
    other, none = lk.issue([BASE])
    assert none == [] and other[0]["seed"] == SEED and other[0]["key"]["attempt"] == ""


def test_owner_changes_seed():
    a = lk.seed_of(lk.digest(lk.key(**BASE, owner="1")))
    b = lk.seed_of(lk.digest(lk.key(**BASE, owner="2")))
    assert a != b


def test_seeds_round_trip_as_int_via_str():
    issued, _ = lk.issue([dict(BASE, source=i) for i in range(50)])
    for row in issued:
        assert 1 <= row["seed"] < 2 ** 63
        assert int(str(row["seed"])) == row["seed"]


def test_forbidden_digest_is_integrity_error():
    with pytest.raises(lk.IntegrityError):
        lk.issue([BASE], forbidden_digests=[DIGEST])
