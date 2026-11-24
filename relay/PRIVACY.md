# Relay Privacy Baseline

The relay routes game traffic between peers. It has no accounts, no player names and no
persisted personal data. This page maps every field it handles, its retention bound and how
a client deletes its IP data. It is the reference for `IP_RETENTION_DAYS` in `relay_server.py`.

## Data map

| Field | Where held | Why | Retention | Publicly exposed? |
| --- | --- | --- | --- | --- |
| Peer IP (`Peer.ip_address`, the open connection's address) | Memory only | Per-IP connection limit (`MAX_CONNECTIONS_PER_IP`), counted over the open connections | Connection lifetime, at most `IP_RETENTION_DAYS` (30 days); `delete_data` blanks `Peer.ip_address` earlier | No — never logged or persisted |
| Peer id, room code | Memory only | Route game frames to the right sockets | Connection / room lifetime | Only the code of a *public* room, in the `rooms_list` browser reply |
| Reconnect token | Memory only | Reclaim the same peer id after a drop | Rejoin window (20 s) | No |
| Aggregate counters (`Stats`) | Memory + JSON file at `RELAY_STATS_PATH` | Usage history across scale-to-zero restarts | Counts, peaks and histograms only | Yes — `GET /stats` and the `get_stats` / `STATS` outputs are aggregate-only |
| Game log line: UTC time to the minute, game system id, sorted faction ids, player count, game version | JSON-lines file at `RELAY_GAMES_PATH` (default: `games.jsonl` next to the stats file, `/data/games.jsonl` on Fly) | Know when games are played and which systems and factions are used | `GAME_LOG_RETENTION_DAYS` = 365 days; each append drops older lines | No — no endpoint serves it and it is not part of `GET /stats`; only the operator reads the volume |
| Game frames | Relayed, never stored | Multiplayer traffic | Not retained | Only to the peers of the sender's room |

## Retention

| Data | Bound |
| --- | --- |
| IP addresses | In memory for the connection lifetime, at most `IP_RETENTION_DAYS` = 30 days |
| Rooms and peers | In memory for the connection / session lifetime only; nothing written to disk |
| Game log | One line per played game, kept 365 days; the relay prunes older lines whenever it appends. A line never holds an IP, room code, peer id, reconnect token, player name, army list, unit list or game outcome |
| Stats file | Aggregate counters, peaks and coarse histograms; contains no IP, room code or player name; `GET /stats` additionally names the serving Fly machine and region (infrastructure ids, not player data) |

## Game log

When a game starts with two or more players over the relay, the host sends one control message

    {"type": "game_meta", "system": "gf", "factions": ["alien_hives"], "players": 2, "version": "0.3.16.0"}

The relay accepts it only from the host of a room that two or more peers joined, once per room, and
only with exactly these keys, short id strings (letters, digits, `_ . + -`), at most 8 factions and
1-8 players. Anything else is dropped and counted in the aggregate `game_meta_rejected`. An accepted
message becomes one line `{"ts", "system", "factions", "players", "version"}`; the connection it came
from (address, room code, peer id, token) is not written. The log is not exposed publicly.

## Deleting your IP data

A connected client may send the WebSocket control message

    {"type": "delete_data"}

The relay then blanks the caller's IP on every in-memory peer record and replies
`{"type": "data_deleted"}`. A caller with no room data gets
`{"type": "error", "reason": "no_data"}`. The game connection itself stays up — routing uses
peer ids and room codes, not IPs. The per-IP connection limit uses the open connection's own
address (behind the hosting proxy: the client address the proxy states for that connection) for
as long as that connection is open; it is gone when the connection closes.

## Logs

IP addresses are never logged. The log stream carries room codes and peer ids (transport
identifiers, not people), the aggregate `STATS` line and error messages only.