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
- A reviewed decision, with legal advice, about records already used in trained or published models — the maintainer's decision (2026-09-13): no legal review, because no user record has ever been uploaded (no send path exists).

The maintainer published these facts on 2026-09-14; the in-game privacy screen shows the same facts in English and German:

- **Destination:** a storage bucket operated by the maintainer of Niemandsland (Cloudflare R2, object storage). Records are uploaded only after you switch sharing on, and only for the games you choose.
- **Controller (the person responsible under the GDPR):** Andreas Kesberg, privacy@niemandsland.xyz.
- **Processor and hosting:** Cloudflare, Inc. (R2 object storage) for shared records; Fly.io, Inc., region Frankfurt (fra), for the multiplayer relay. The relay processes your IP address and a per-install reconnect token to route your game; neither is written to a log, and the retention bound is 30 days.
- **Recipients:** nobody but the maintainer. Records are not sold, not shared with third parties, and never used for advertising.
- **Retention:** shared records are kept until you request deletion with your deletion code, or until the maintainer retires the evaluation corpus; relay connection data at most 30 days.
- **Withdrawal:** available on the in-game privacy screen at any time and stops future sharing immediately. Deletion request: send your deletion code (shown on that screen) to privacy@niemandsland.xyz; every record carrying it is deleted.
- **Contact and privacy notice:** privacy@niemandsland.xyz; the full notice is this document. **Supervisory authority:** the data-protection authority of the German federal state of the controller (see bfdi.bund.de for the list).
- **Lawful basis:** consent (Art. 6(1)(a) GDPR), separately for evaluation and for training, revocable here.

Until a collector and a separately reviewed per-game veto milestone exist, the product remains local-only and sends nothing.
