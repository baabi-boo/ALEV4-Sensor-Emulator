# Retained Phase 4 candidate evidence

This directory preserves the original acceptance evidence for implementation
candidate [`ad036efe6bb6d298545055df37cc4b4681c3e8da`](https://github.com/baabi-boo/ALEV4-Sensor-Emulator/commit/ad036efe6bb6d298545055df37cc4b4681c3e8da),
Git tree `34bf3899c4903a6283ae344076983f948fddfc19`. The local GNU Octave
9.4.0 and CI GNU Octave 8.4.0 receipts each report **20/20 command gates
passed**, clean source before/after, `development=false`, and
`release_accepted=true`. The reports retain 111 Phase 4 numerical groups,
135 Phase 3, 62 Phase 2, 92 Phase 1, and the full 316-test Python log.
Their exact commands, exits, runtime and source/dependency identities remain
unchanged. [Local receipt](local/acceptance.json), [CI receipt](ci/acceptance.json)

The retained observations show all five candidate workflows completed
successfully. The Phase 4 run is
[43795168396](https://github.com/baabi-boo/ALEV4-Sensor-Emulator/actions/runs/43795168396),
job [133062224124](https://github.com/baabi-boo/ALEV4-Sensor-Emulator/actions/runs/43795168396/job/133062224124),
artifact **14194742079**. These are the recorded observations of this candidate,
not a live status assertion about a later commit.
[Workflow snapshot](ci-run/candidate_run_summary.json),
[artifact metadata](ci-run/artifact_metadata.json)

## Retained contents

| Path | Scope |
| --- | --- |
| `ci-evidence-ad036ef.zip` | Byte-identical original CI artifact: all 402 files, 18,400,875 expanded bytes. |
| `local/` and `ci/` | Readable aggregate receipts; complete Phase 4 numerical reports including all nested earlier gates; the nested regression files; four artifact-verifier receipts; all four runner-control receipts; dependency and numerical stdout; full Python stderr; selected empty stderr. Original relative paths are preserved. |
| `local/phase4-candidate-time.json` | Original local timing/exit receipt. Its child maximum RSS is not simultaneous aggregate peak memory or a full-frame benchmark. |
| `ci-run/` | Original workflow, artifact, job and download-digest metadata with public GitHub URLs. |
| `independent/` | Wave 9a independent semantic audit, all four executed verifier JSON outputs, exact execution receipts and empty stderr files; Wave 9d selected cross-runtime native readback receipt. |
| `post-candidate/w08_f/` | Focused corrected diagnostic output, numeric-metric audit and exact Octave harness from the later dirty worktree. |
| `manifest.json` | Source associations, public run/artifact identifiers, limitations, source-copy verification, and every other retained file's relative path, byte size and SHA-256. |

The ZIP is **1,393,948 bytes**, SHA-256
`dd1ad67edb8fbc5e14050f97f89cd365eacc61d1972c662d3706ac781349b966`.
Its content is retained without recompression. The readable CI files are exact
copies of their corresponding ZIP members. The readable trees are intentionally
partial selections: use the ZIP for all logs, demonstration payloads, summaries
and independent artifact re-verification. In particular, the original large
numerical stderr logs are inside the ZIP, not duplicated as expanded files.
The original local full artifact tree is not duplicated here; its complete
hash inventory remains in `local/acceptance.json`.

Every copied source was read without mutation and compared byte-for-byte after
copy. Both original 401-entry aggregate inventories and all 402 ZIP members
were checked against their source files during retention. The manifest does
not hash itself; Git records its own bytes. It inventories `README.md` as new
retention documentation rather than historical execution evidence. The
manifest records total bytes including its own final serialized size.

## Candidate and later diagnostic correction

The candidate's passing `normal_boundary_and_signed_cancellation` assertions
precede a diagnostic-fidelity limitation: native JSON serialized the numeric
`smallest_normal_accepted` metric as **0**. Both original numerical reports
and the CI ZIP preserve that historical value. It must not be read as an exact
`realmin` value, and retaining it is not a claim that the scientific assertion
failed. [Independent audit](independent/w09_a-ci-semantic-audit.json)

The later focused correction stores the smallest-normal and adjacent-Poisson
boundary diagnostics as decimal text. Its source was **HEAD `ad036ef` plus an
uncommitted edit** to `matlab/tests/test_phase4_numerical_edges.m`, SHA-256
`05568045ddbbb73c8fc95bc9ddbcb6b2fcff5fe068d6c676f2e946bae5e0948d`.
The retained corrected report records **14/14 existing numerical-edge groups**
under GNU Octave 9.4.0; the accompanying audit covers 40 remaining numeric
metric scalars. This changes reporting and serialization assertions, with the
scientific predicates and 111-group inventory unchanged. It is **focused dirty
worktree evidence**, not complete clean-source acceptance of the corrected
file or of any later documentation/evidence commit. No final publication SHA
is invented here. [Focused report](post-candidate/w08_f/numerical-edges.json),
[metric audit](post-candidate/w08_f/numeric-metric-audit.json),
[original harness](post-candidate/w08_f/targeted_edges.m),
[execution account](../../development/phase4/agent-reports/w08_f.md)

The harness is historical input and contains its original output path. Do not
run it against a retained evidence directory. Reproducing the correction
requires the exact corrected test source and a fresh output location; the
candidate checkout alone contains the earlier diagnostic representation.

## Verify the copies, extract and recheck the actual artifacts

Run the following from the repository root with Python 3.10 or newer and the
candidate Git object available. It verifies the retained manifest, checks the
candidate tree, extracts into a newly created temporary directory, checks the
complete archived acceptance inventory, and runs all four artifact verifiers
with the **full candidate SHA**. It obtains the verifier code from the candidate
Git object, so later worktree edits cannot silently change this recheck.
It writes its outputs only into that new temporary directory and prints its
location; it does not rerun Octave or numerical acceptance.

```bash
python3 -B - <<'PY'
from pathlib import Path, PurePosixPath
import hashlib, json, os, stat, subprocess, sys, tempfile, zipfile

root = Path.cwd()
evidence = root / 'docs/evidence/phase4'
manifest = json.loads((evidence / 'manifest.json').read_text())
sha = lambda data: hashlib.sha256(data).hexdigest()
for item in manifest['files']:
    path = evidence / item['path']
    assert path.is_file() and not path.is_symlink(), path
    data = path.read_bytes()
    assert len(data) == item['bytes'] and sha(data) == item['sha256'], path
assert sum(p.stat().st_size for p in evidence.rglob('*') if p.is_file()) == manifest['retention']['total_bytes_including_manifest']
expected = manifest['candidate']['commit']
assert subprocess.check_output(
    ['git', 'rev-parse', expected + '^{tree}'], text=True).strip() == manifest['candidate']['tree']
work = Path(tempfile.mkdtemp(prefix='alev4-phase4-recheck-'))
expanded = work / 'extracted'
expanded.mkdir()
with zipfile.ZipFile(evidence / 'ci-evidence-ad036ef.zip') as archive:
    members = archive.infolist()
    assert len(members) == len({m.filename for m in members}) == 402
    for member in members:
        rel = PurePosixPath(member.filename)
        assert not rel.is_absolute() and '..' not in rel.parts
        assert not member.is_dir() and not stat.S_ISLNK(member.external_attr >> 16)
        target = expanded / member.filename
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open('xb') as output:
            output.write(archive.read(member))
acceptance = json.loads((expanded / 'acceptance.json').read_text())
assert acceptance['source_revision'] == expected
assert acceptance['source_tree'] == manifest['candidate']['tree']
assert len(acceptance['files']) == 401
for relative, item in acceptance['files'].items():
    data = (expanded / relative).read_bytes()
    assert len(data) == item['bytes'] and sha(data) == item['sha256'], relative
code = work / 'candidate-verifiers'
code.mkdir()
audit = json.loads((evidence / 'independent/w09_a-ci-semantic-audit.json').read_text())
for phase in range(1, 5):
    relative = f'scripts/verify_phase{phase}_artifacts.py'
    data = subprocess.check_output(['git', 'show', f'{expected}:{relative}'])
    assert sha(data) == audit['candidate_identical_verifiers'][relative]['sha256']
    with (code / Path(relative).name).open('xb') as output:
        output.write(data)
for phase in range(1, 5):
    phase_root = expanded / f'phase{phase}'
    argv = [sys.executable, '-B', str(code / f'verify_phase{phase}_artifacts.py'),
            str(phase_root), '--expected-commit', expected,
            '--compare-dir', str(phase_root / 'demo-repeat')]
    with (work / f'phase{phase}-recheck.json').open('xb') as stdout, \
         (work / f'phase{phase}-recheck.stderr.txt').open('xb') as stderr:
        subprocess.run(argv, check=True, stdout=stdout, stderr=stderr,
                       env={**os.environ, 'PYTHONDONTWRITEBYTECODE': '1'})
print('Verified retained files and all four artifact sets:', work)
PY
```

The independent Wave 9a audit already executed all four verifiers against the
downloaded bytes with Python 3.12.14; all exits were zero, all stderr empty,
and all outputs byte-identical to the archived verifier receipts. It also
checked commands, nested prerequisites, source labels, dependency logs, repeat
file identities and the full archive inventory. Its execution receipts retain
exact argv and timestamps. That audit did not rerun native numerical gates or
Python unit tests; those results remain the original acceptance evidence.

A separate [native readback receipt](independent/w09_d-native-readback.json)
records four selected CI bundles produced by GNU Octave 8.4.0 and successfully
read and explicitly validated under GNU Octave 9.4.0. It checks single, dual,
spatial and sequence data, caller RNG, handles and unchanged source bytes.
All 52 production MATLAB files match the candidate. The receipt preserves an
initial probe helper-scope error and the successful four-read invocation; it
establishes limited wire readability, not PRNG replay, generation identity,
all-24 native readback coverage or native MATLAB execution.

## Interpretation limits

All sensor/noise maps and parameter magnitudes are assumed; the artifacts are
synthetic and the research model is uncalibrated. Neither these runs nor the
byte verifiers establish measured ALEV4/ARRI noise or dynamic range, genuine
ARRIRAW, camera identity, proprietary calibration, or full-frame resource
performance. Native MATLAB execution remains **unverified**. Repeatability is
scoped to the recorded runtime/version and does not promise identical MATLAB
and Octave random streams. Semantic artifact verification does not authenticate
PRNG origin/distributions or claimed input sources. The fixture-control counts
are reporting controls, separate from scientific numerical groups: the Phase 4
receipt has 163 listed scenarios (162 exit-one failures and one exit-zero
core-only case), plus one separately counted complete positive fixture control.
