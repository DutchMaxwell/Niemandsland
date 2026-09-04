# Optional game-record sharing: current facts

Niemandsland currently sends no game records. There is no upload URL, upload client, background queue, retry path, or collector in this version. The privacy screen can only build a committed example through the real allowlist builder, preview those exact bytes, and save those same bytes locally to `user://shared_records/example.json` when the player explicitly asks.

The settings default to off. Evaluation sharing and training use are separate choices in `user://privacy.json`; training use cannot be on unless evaluation sharing is on. The one-time prompt appears only after a completed game and is marked seen when first shown, so dismissing it or choosing **No thanks** cannot cause another automatic prompt. Both choices can be withdrawn immediately on the same details page.

## Exact structured fields

The builder accepts only these fields and canonicalises them as sorted, compact UTF-8 JSON:

- Payload and consent schema versions; a random 128-bit hexadecimal per-install deletion code; record identifier.
- Game version/build hash, core ABI and rules epoch; separate training-use choice.
- Public opponent engine/id/hash; game-system, mission and scoring identifiers; known random/layout/dice seeds.
- Table dimensions; terrain and objective type identifiers, coordinates, rotations and numeric owners.
- Armies by numeric side, stable book/faction/unit/profile/loadout/rule identifiers, and numeric quality, defence and model count.
- Ordered actions by index, round, numeric side, stable unit/action/target identifiers, numeric coordinates, observed dice faces and numeric score.
- Round count, final victory points, objective owners and outcome identifier.
- `payload_sha256`, computed over the canonical allowlisted object before that hash field is added.

Unknown keys and invalid identifier strings are dropped. The format has no free-text or wall-clock timestamp field. It never reads a save file, diagnostics report, multiplayer identity, chat or battle-log text.

## Never included

Player, army and unit display names; chat; battle-log prose; room codes; multiplayer identity tokens; account, platform, device or IP identifiers; save files; screenshots; timestamps; filesystem paths; host names; hardware inventory; unrelated diagnostics.

## Facts the maintainer must publish before any sending feature

- Destination and controller identity/contact.
- Processor, hosting region, recipients, and actual infrastructure logging behaviour.
- Exact purposes and lawful basis for evaluation and separately for training.
- Raw/quarantine retention and the deletion/tombstoning policy for derived fixtures and future corpora.
- Withdrawal and deletion-request route, privacy-notice/imprint URL, and supervisory-authority route.
- A reviewed decision, with legal advice, about records already used in trained or published models.

Until those facts, a collector, and a separately reviewed per-game veto milestone all exist, the product remains local-only and sends nothing.
