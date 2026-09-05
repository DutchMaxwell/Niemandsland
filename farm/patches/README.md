# Fleet recorder identity compatibility

The independently maintained `gen0_one.py` and `gen1_one.py` are not tracked
in this repository. `preserve-core-identity.patch` adds only the dictionary
merge needed to retain `play_game`'s build stamps in their existing writers.
It does not contain or publish the private drivers.

Apply from the directory containing those two files, only while they are not
running:

```sh
git apply --check /path/to/repo/farm/patches/preserve-core-identity.patch
git apply /path/to/repo/farm/patches/preserve-core-identity.patch
```

Run the integration test against those files with the installed core wheel:

```sh
NML_FARM_RECORDERS=/path/to/recorders PYTHONPATH=core/nml-core-py/python \
  python -m pytest core/nml-core-py/tests/python/test_farm_core_identity.py -q
```

Set `NML_FARM_IDENTITY_PATCH=1` as well to test the patch on temporary copies
of the unpatched drivers without modifying the originals. The test passes a
real core-produced game through each driver's actual `main()` and JSON writer;
it substitutes the game-return call and disables model execution. It verifies
both stamps and strict gate acceptance without the legacy top-level stamp.
Without external drivers configured, these two integration tests explicitly
skip; the legacy compatibility CLI matrix still runs in ordinary CI.

The gate also accepts the top-level `core_commit` retained by old fleet records.
`prescreen.core_commit` takes precedence when both stamps are present.
