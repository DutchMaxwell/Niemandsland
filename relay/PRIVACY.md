# Relay Privacy Baseline

The relay routes game traffic between peers. It has no accounts, no player names and no
persisted personal data. This page maps every field it handles, its retention bound and how
a client deletes its IP data. It is the reference for `IP_RETENTION_DAYS` in `relay_server.py`.

## Data map

| Field | Where held | Why | Retention | Publicly exposed? |
| --- | --- | --- | --- | --- |
| Peer IP (`Peer.ip_address`, `ip_connection_counts`) | Memory only | Per-IP connection limit (`MAX_CONNECTIONS_PER_IP`) | Connection lifetime, at most `IP_RETENTION_DAYS` (30 days); erased earlier by `delete_data` | No — never logged or persisted |
| Peer id, room code | Memory only | Route game frames to the right sockets | Connection / room lifetime | Only the code of a *public* room, in the `rooms_list` browser reply |
| Reconnect token | Memory only | Reclaim the same peer id after a drop | Rejoin window (20 s) | No |
| Aggregate counters (`Stats`) | Memory + JSON file at `RELAY_STATS_PATH` | Usage history across scale-to-zero restarts | Counts, peaks and histograms only | Yes — `GET /stats` and the `get_stats` / `STATS` outputs are aggregate-only |
| Game frames | Relayed, never stored | Multiplayer traffic | Not retained | Only to the peers of the sender's room |

## Retention

| Data | Bound |
| --- | --- |
| IP addresses | In memory for the connection lifetime, at most `IP_RETENTION_DAYS` = 30 days |
| Rooms and peers | In memory for the connection / session lifetime only; nothing written to disk |
| Stats file | Aggregate counters, peaks and coarse histograms; contains no IP, room code or player name |

## Deleting your IP data

A connected client may send the WebSocket control message

    {"type": "delete_data"}

The relay then removes the caller's IP from `ip_connection_counts` and blanks it on every
in-memory peer record, and replies `{"type": "data_deleted"}`. A caller with no room data gets
`{"type": "error", "reason": "no_data"}`. The game connection itself stays up — routing uses
peer ids and room codes, not IPs.

## Logs

IP addresses are never logged. The log stream carries room codes and peer ids (transport
identifiers, not people), the aggregate `STATS` line and error messages only.