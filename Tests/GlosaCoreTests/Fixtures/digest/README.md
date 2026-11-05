# Render digest golden vectors

Each `*.json` file is one vector:

```json
{ "shot": { …bare shot object, schema form… }, "sha256": "<lowercase hex>" }
```

`FoldDigestTests` decodes `shot` with `Shot(schemaJSON:)` and checks that its
`renderDigest` equals `sha256`. Each `shot` is treated as already effective (no fold).

The hashes were computed independently of the Swift code: a one-off Python script
(not committed) that applies RFC 8785 (UTF-16 key order, ECMAScript number
formatting) to the shot minus `caption`, `output`, `preview`, `telemetry`, `id`,
`move`, `discovered` and `reorder`, with `seed` as a decimal string, then SHA-256 over
the UTF-8 bytes.

Vectors `08`–`13` cover the one amendment to the freeze (D-15). `08` is the baseline,
`09`–`12` add one excluded key each and carry the same hash, and `13` changes `view`,
which stays in the preimage. Vectors `01`–`07` predate the amendment and hold none of
those four keys, so their hashes did not change.

The digest preimage is frozen for notation 2.x, and D-15 is its only amendment. Never
regenerate these hashes to match a code change; a mismatch means the code broke the
digest. All content is synthetic.
