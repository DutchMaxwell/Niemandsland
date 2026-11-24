#!/usr/bin/env python3
"""Summarise the relay's anonymous per-game log (games.jsonl): games per day and per version, and
how often each game system and faction was played. The log holds no IPs, room codes or names.

Usage:
  flyctl ssh console -a niemandsland-relay -C "cat /data/games.jsonl" > games.jsonl
  python games_digest.py games.jsonl
"""
import json
import sys
from collections import Counter


def digest(lines) -> dict:
    """Count per-day, per-version, per-system and per-faction from JSON lines; skip bad lines."""
    counts = {"days": Counter(), "versions": Counter(), "systems": Counter(),
              "factions": Counter(), "players": Counter()}
    for line in lines:
        try:
            game = json.loads(line)
            day = str(game["ts"])[:10]
        except (ValueError, TypeError, KeyError):
            continue
        counts["days"][day] += 1
        counts["versions"][str(game.get("version", "?"))] += 1
        counts["systems"][str(game.get("system", "?"))] += 1
        counts["players"][str(game.get("players", "?"))] += 1
        for faction in game.get("factions", []) or []:
            counts["factions"][str(faction)] += 1
    return counts


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    with open(sys.argv[1], encoding="utf-8") as f:
        counts = digest(f)
    print(f"games: {sum(counts['days'].values())}")
    for title, key, by_key in (("per day", "days", True), ("per version", "versions", True),
                               ("players", "players", True), ("systems", "systems", False),
                               ("factions", "factions", False)):
        print(f"\n{title}:")
        items = sorted(counts[key].items()) if by_key else counts[key].most_common()
        for name, n in items:
            print(f"  {name:<28} {n}")


if __name__ == "__main__":
    main()
