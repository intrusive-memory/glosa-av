# Render digest golden vectors

Each `*.json` file is one vector:

```json
{ "shot": { …bare shot object, schema form… }, "sha256": "<lowercase hex>" }
```

`FoldDigestTests` decodes `shot` with `Shot(schemaJSON:)` and checks that its
`renderDigest` equals `sha256`. Each `shot` is treated as already effective (no fold).

The hashes were computed independently of the Swift code: a one-off Python script
(not committed) that applies RFC 8785 (UTF-16 key order, ECMAScript number
formatting) to the shot minus `caption`, `output`, `preview` and `telemetry`, with
`seed` as a decimal string, then SHA-256 over the UTF-8 bytes.

The digest preimage is frozen for notation 2.x. Never regenerate these hashes to
match a code change; a mismatch means the code broke the digest. All content is synthetic.
