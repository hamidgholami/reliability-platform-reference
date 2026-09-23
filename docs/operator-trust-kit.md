# Operator Trust Kit

The operator trust kit is the minimum material needed to establish and recover
trust without depending on the platform being healthy.

## Required contents

- verified repository revision and release checksums;
- documented maintainers and emergency decision process;
- DNS registrar and authoritative-DNS recovery procedure;
- offline locations for CA recovery material and OpenBao recovery keys;
- bootstrap host fingerprints and out-of-band access procedure;
- encrypted inventory of cloud accounts, tenants, and billing contacts;
- restore order, last tested date, and evidence location;
- credential-rotation checklist after suspected exposure.

## Storage rules

The kit specification belongs in Git; its secrets do not. Recovery keys, private
keys, tokens, TOTP seeds, and unredacted inventories must be encrypted outside
the repository with at least two independently recoverable custodians or
locations. Examples in this repository must be synthetic.

## Bootstrap trust ceremony

1. Verify the human operator and the signed repository revision out of band.
2. Verify DNS registrar and authoritative-DNS control.
3. Verify host fingerprints before accepting SSH access.
4. Establish or restore the internal CA and secrets service.
5. Issue short-lived credentials; do not distribute reusable deployment keys.
6. Record the ceremony, participants, revision, and validation evidence.

The detailed executable ceremony and recovery drill arrive with the foundation
and secrets phases. Phase 0 defines the contract only.
