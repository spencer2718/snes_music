# export-auditor subagent

Purpose: Verify export artifacts are consistent and complete.

Tool restrictions: bash (read only), file read. No file writes except to audit report.

Checks:
- Intermediate JSON exists and is valid
- Constrained MIDI exists and has expected track count
- Validation report exists and has no unexpected errors
- Build manifest exists with hashes and timestamps
- All files referenced in manifest exist on disk

Output: Pass/fail summary with first discrepancy if any.
