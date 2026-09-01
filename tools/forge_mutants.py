#!/usr/bin/env python3
"""forge_mutants.py — ask a LOCAL model to kill ONE cargo-mutants survivor at a
time. For each `missed.txt`-style survivor line: extract the enclosing Rust
fn, fetch the mutant's unified diff (`cargo mutants --list --diff`), prompt a
local Ollama model (default `JetBrains/mellum2-instruct-mxfp4_moe`,
http://localhost:11434/api/generate) for exactly one `#[test]` fn, and decide
by RUNNING THE MACHINE — never by reading the model's prose.

ACCEPT rule, all four gates in order, any failure is a machine-checked REJECT:
  1. format — reply is exactly one ```rust block, exactly one fn, exactly one
     #[test] attribute.
  2. green  — spliced into the tests module unmodified, `cargo test --lib
     <path> -- --exact` PASSES.
  3. kill   — with the mutant diff applied on top (`patch -p0`, never `git
     checkout`, so earlier --apply splices in the same file survive), the
     SAME test FAILS. The mutant is then reverted with the reverse patch,
     keeping the splice.
  4. suite  — the whole `cargo test --lib` still passes.
Reject reasons: format, green_fail, not_killed, suite_broken, no_diff,
patch_failed, error. The model's own opinion of its test never enters.

Usage: forge_mutants.py --survivors missed.txt --crate core/nml-core --out OUT
    [--limit N] [--apply] [--model NAME] [--dry-run] [--force-noop-diff]
--force-noop-diff is the RED proof: every target's "mutant diff" becomes a
no-op, so gate 3 can never pass — proves the gate can actually fail.
"""
import argparse, json, re, subprocess, sys, time, urllib.request
from pathlib import Path

TARGET_RE = re.compile(r'^(?P<file>\S+):(?P<line>\d+):(?P<col>\d+):\s*(?P<desc>.+)$')
FN_DEF_RE = re.compile(r'^\s*(pub(\([^)]*\))?\s+)?(async\s+)?fn\s+(?P<name>[A-Za-z_]\w*)\s*\(', re.M)
TEST_MOD_RE = re.compile(r'#\[cfg\(test\)\]\s*\n\s*mod\s+tests\s*\{')
RUST_BLOCK_RE = re.compile(r'```rust\s*\n(.*?)```', re.S)

def parse_survivors(path, limit=None):
    targets = []
    for raw in Path(path).read_text().splitlines():
        raw = raw.strip()
        if not raw or raw.startswith('#'):
            continue
        m = TARGET_RE.match(raw)
        if not m:
            continue
        targets.append({'file': m['file'], 'line': int(m['line']), 'col': int(m['col']),
                         'desc': m['desc'], 'raw': raw})
    return targets[:limit] if limit else targets

def scan_to_close(lines, start_idx):
    """First line index where brace depth returns to 0, scanning from start_idx
    (naive char scan — no string/comment awareness; acceptable for this
    house-style crate)."""
    depth, seen = 0, False
    for i in range(start_idx, len(lines)):
        for ch in lines[i]:
            if ch == '{':
                depth += 1
                seen = True
            elif ch == '}' and seen:
                depth -= 1
                if depth == 0:
                    return i
    return None

def extract_fn(file_path, target_line):
    lines = Path(file_path).read_text().split('\n')
    fn_idx = fn_name = None
    for i in range(target_line - 1, -1, -1):
        m = FN_DEF_RE.match(lines[i])
        if m:
            fn_idx, fn_name = i, m['name']
            break
    if fn_idx is None:
        raise ValueError(f'no enclosing fn found above {file_path}:{target_line}')
    start_idx, j = fn_idx, fn_idx - 1
    while j >= 0 and (lines[j].strip().startswith('///') or lines[j].strip().startswith('#[')):
        start_idx, j = j, j - 1
    end_idx = scan_to_close(lines, fn_idx)
    if end_idx is None:
        raise ValueError(f'unbalanced braces scanning fn {fn_name} in {file_path}')
    return fn_name, '\n'.join(lines[start_idx:end_idx + 1])

def find_tests_module(lines):
    text = '\n'.join(lines)
    starts = [m.start() for m in TEST_MOD_RE.finditer(text)]
    if not starts:
        return None
    mod_kw_pos = text.index('mod tests', starts[-1])
    mod_line_idx = text.count('\n', 0, mod_kw_pos)
    close_idx = scan_to_close(lines, mod_line_idx)
    return None if close_idx is None else (mod_line_idx, close_idx)

def style_and_helpers(lines, mod_range, target_fn_name):
    mod_line_idx, close_idx = mod_range
    tests, i = [], mod_line_idx + 1
    while i < close_idx:
        if lines[i].strip() == '#[test]':
            j = i + 1
            while j < close_idx and not FN_DEF_RE.match(lines[j]):
                j += 1
            if j < close_idx:
                end = scan_to_close(lines, j)
                if end is not None:
                    body = '\n'.join(lines[i:end + 1])
                    tests.append((FN_DEF_RE.match(lines[j])['name'], body, end - i + 1))
                    i = end
        i += 1
    sample = next((t for t in tests if target_fn_name in t[1]), None)
    sample = sample or (min(tests, key=lambda t: t[2]) if tests else None)
    helpers, i = [], mod_line_idx + 1
    while i < close_idx:
        m = FN_DEF_RE.match(lines[i])
        prev = lines[i - 1].strip() if i > 0 else ''
        if m and prev != '#[test]':
            helpers.append(lines[i].strip())
        i += 1
    return sample, helpers

ENTRY_HEADER_RE = re.compile(r'^(?P<file>\S+):(?P<line>\d+):(?P<col>\d+): (?P<desc>.+)$', re.M)

def parse_list_diff_output(text):
    matches = list(ENTRY_HEADER_RE.finditer(text))
    entries = {}
    for i, m in enumerate(matches):
        end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        entries[(m['file'], int(m['line']), int(m['col']))] = {
            'desc': m['desc'], 'diff': text[m.end():end].strip('\n')}
    return entries

def build_diffs_cache(crate_dir, targets, out_dir):
    """One `--list --diff` call per FILE (grouped), not per target — cached
    to <out>/diffs.json so a slow crate only pays this once."""
    by_file = {}
    for t in targets:
        by_file.setdefault(t['file'], []).append(t)
    cache = {}
    for file, ts in by_file.items():
        pattern = '|'.join(re.escape(t['desc']) for t in ts)
        proc = subprocess.run(
            ['cargo', 'mutants', '--list', '--diff', '-F', pattern, '--file', file],
            cwd=crate_dir, capture_output=True, text=True, timeout=120)
        entries = parse_list_diff_output(proc.stdout)
        for t in ts:
            key = (t['file'], t['line'], t['col'])
            if key in entries:
                cache[t['raw']] = entries[key]
    (Path(out_dir) / 'diffs.json').write_text(json.dumps(cache, indent=2))
    return cache

def make_noop_diff(crate_dir, target):
    """RED-proof helper: a syntactically valid unified diff that replaces a
    line with itself — applies cleanly, changes nothing."""
    lines = (Path(crate_dir) / target['file']).read_text().split('\n')
    content = lines[target['line'] - 1]
    return (f"--- {target['file']}\n+++ {target['file']}\n"
            f"@@ -{target['line']},1 +{target['line']},1 @@\n-{content}\n+{content}")

def build_prompt(fn_name, fn_source, target, diff_text, sample, helpers):
    parts = [
        "You are a Rust test engineer hardening a rules-engine crate against cargo-mutants survivors.",
        "", f"Function under test (`{fn_name}`):", "```rust", fn_source, "```", "",
        f"A cargo-mutants mutant survived: {target['desc']}",
        "Diff (unified, paths relative to the crate root):", "```diff", diff_text, "```",
        "Write ONE #[test] fn that PASSES on the original code and FAILS on this mutant.",
    ]
    if sample:
        parts += ["", f"House style — an existing test from this file's tests module (`{sample[0]}`):",
                  "```rust", sample[1], "```"]
    if helpers:
        parts += ["", "Fixture helpers already defined in the tests module (call them, do not redefine them):"]
        parts += [f"- {h}" for h in helpers]
    parts += ["", "Reply with ONLY one ```rust block containing exactly one #[test] fn, "
              "<= 25 lines, house style, no prose, no comments explaining your reasoning."]
    return '\n'.join(parts)

def call_ollama(url, model, prompt):
    payload = json.dumps({"model": model, "prompt": prompt, "stream": False,
                           "options": {"num_ctx": 8192, "temperature": 0.2}}).encode()
    req = urllib.request.Request(url, data=payload, headers={'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=300) as resp:
        return json.loads(resp.read())

def extract_test(response_text):
    m = RUST_BLOCK_RE.search(response_text)
    if not m:
        return None, 'format'
    code = m.group(1).strip('\n')
    if code.count('#[test]') != 1 or len(FN_DEF_RE.findall(code)) != 1:
        return None, 'format'
    return code, None

def unique_name(name, existing):
    if name not in existing:
        return name
    i = 2
    while f'{name}_forge{"" if i == 2 else i}' in existing:
        i += 1
    return f'{name}_forge' if i == 2 else f'{name}_forge{i}'

def splice_test(file_path, code):
    lines = Path(file_path).read_text().split('\n')
    mod_range = find_tests_module(lines)
    if mod_range is None:
        raise ValueError('no #[cfg(test)] mod tests block found')
    mod_line_idx, close_idx = mod_range
    existing = {FN_DEF_RE.match(l)['name'] for l in lines if FN_DEF_RE.match(l)}
    orig_name = FN_DEF_RE.search(code)['name']
    new_name = unique_name(orig_name, existing)
    if new_name != orig_name:
        code = re.sub(rf'\bfn\s+{re.escape(orig_name)}\b', f'fn {new_name}', code, count=1)
    indented = '\n'.join(('    ' + l if l.strip() else l) for l in code.split('\n'))
    lines = lines[:close_idx] + ['', indented] + lines[close_idx:]
    Path(file_path).write_text('\n'.join(lines))
    return new_name

def module_path_of(file_rel):
    p = file_rel[len('src/'):] if file_rel.startswith('src/') else file_rel
    p = p[:-3] if p.endswith('.rs') else p
    p = p[:-4] if p.endswith('/mod') else p
    return p.replace('/', '::')

def run_filtered_test(crate_dir, full_path, want):
    """want = 'ok' or 'FAILED'. Confirms the SPECIFIC test ran with that
    outcome (an empty filter match would otherwise pass trivially)."""
    proc = subprocess.run(['cargo', 'test', '--lib', full_path, '--', '--exact'],
                           cwd=crate_dir, capture_output=True, text=True, timeout=180)
    out = proc.stdout + proc.stderr
    return f'test {full_path} ... {want}' in out, out

def run_full_suite(crate_dir):
    proc = subprocess.run(['cargo', 'test', '--lib'], cwd=crate_dir,
                           capture_output=True, text=True, timeout=300)
    return proc.returncode == 0

def apply_patch(crate_dir, diff_text, reverse=False):
    if not diff_text.endswith('\n'):
        diff_text += '\n'  # patch(1) rejects a patch with no trailing newline
    cmd = ['patch', '-p0'] + (['-R'] if reverse else [])
    proc = subprocess.run(cmd, cwd=crate_dir, input=diff_text, capture_output=True, text=True)
    return proc.returncode == 0

def process_target(n, t, crate_dir, out_dir, args, diffs):
    """Returns one record dict, or None if a target had to be skipped before
    any file was touched (no fn found)."""
    file_path = crate_dir / t['file']
    fn_name, fn_source = extract_fn(file_path, t['line'])

    diff_text = make_noop_diff(crate_dir, t) if args.force_noop_diff else diffs.get(t['raw'], {}).get('diff')
    base = {'target': t['raw'], 'fn': fn_name, 'prompt_tokens': None, 'eval_tokens': None,
            'seconds': None, 'verdict': 'reject', 'reason': None, 'test_source': None}
    if not diff_text:
        return {**base, 'reason': 'no_diff'}
    lines = Path(file_path).read_text().split('\n')
    mod_range = find_tests_module(lines)
    sample, helpers = (None, []) if mod_range is None else style_and_helpers(lines, mod_range, fn_name)
    prompt = build_prompt(fn_name, fn_source, t, diff_text, sample, helpers)
    if args.dry_run:
        (out_dir / f'{n}_{fn_name}_prompt.txt').write_text(prompt)
        print(f'=== [{n}] {t["raw"]} ===\n{prompt}\n')
        return None

    data = call_ollama(args.ollama_url, args.model, prompt)
    base.update(prompt_tokens=data.get('prompt_eval_count'), eval_tokens=data.get('eval_count'),
                seconds=data.get('total_duration', 0) / 1e9)
    code, reason = extract_test(data.get('response', ''))
    if reason:
        return {**base, 'reason': reason}
    original_text = Path(file_path).read_text()

    def reject(reason):
        Path(file_path).write_text(original_text)
        return {**base, 'reason': reason, 'test_source': code}

    try:
        test_name = splice_test(file_path, code)
        full_path = f"{module_path_of(t['file'])}::tests::{test_name}"
        ok, _ = run_filtered_test(crate_dir, full_path, 'ok')
        if not ok:
            return reject('green_fail')
        if not apply_patch(crate_dir, diff_text):
            return reject('patch_failed')
        killed, _ = run_filtered_test(crate_dir, full_path, 'FAILED')
        apply_patch(crate_dir, diff_text, reverse=True)  # always undo the mutant
        if not killed:
            return reject('not_killed')
        if not run_full_suite(crate_dir):
            return reject('suite_broken')
        if not args.apply:
            Path(file_path).write_text(original_text)
        return {**base, 'verdict': 'accept', 'test_source': code}
    except Exception as e:  # noqa: BLE001 — never leave the tree half-patched
        return reject(f'error: {e}')

def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('--survivors', required=True)
    ap.add_argument('--crate', default='core/nml-core')
    ap.add_argument('--limit', type=int, default=None)
    ap.add_argument('--out', required=True)
    ap.add_argument('--apply', action='store_true')
    ap.add_argument('--model', default='JetBrains/mellum2-instruct-mxfp4_moe')
    ap.add_argument('--ollama-url', default='http://localhost:11434/api/generate')
    ap.add_argument('--dry-run', action='store_true')
    ap.add_argument('--force-noop-diff', action='store_true',
                     help='RED proof: substitute a no-op diff for every target.')
    args = ap.parse_args()

    crate_dir = Path(args.crate).resolve()
    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    targets = parse_survivors(args.survivors, args.limit)
    if not targets:
        print('no survivors parsed', file=sys.stderr)
        return 1

    diffs = {} if args.force_noop_diff else build_diffs_cache(crate_dir, targets, out_dir)
    report_lines = []
    totals = {'accepted': 0, 'reject_reasons': {}, 'prompt_tokens': 0, 'eval_tokens': 0}
    wall_start = time.time()

    for n, t in enumerate(targets, 1):
        try:
            record = process_target(n, t, crate_dir, out_dir, args, diffs)
        except ValueError as e:
            print(f'[{n}] {t["raw"]}: {e}', file=sys.stderr)
            continue
        if record is None:  # dry-run: prompt already printed/written
            continue
        totals['prompt_tokens'] += record['prompt_tokens'] or 0
        totals['eval_tokens'] += record['eval_tokens'] or 0
        _finish(record, n, out_dir, report_lines, totals)

    if args.dry_run:
        print(f'DRY RUN: {len(targets)} prompts built in {out_dir}, no model called, no files touched.')
        return 0
    (out_dir / 'report.jsonl').write_text('\n'.join(report_lines) + ('\n' if report_lines else ''))
    wall = time.time() - wall_start
    print(f"targets={len(targets)} accepted={totals['accepted']} "
          f"rejected={sum(totals['reject_reasons'].values())} {totals['reject_reasons']}")
    print(f"tokens: prompt={totals['prompt_tokens']} eval={totals['eval_tokens']} wall_seconds={wall:.1f}")
    if args.apply:
        proc = subprocess.run(['git', 'diff', '--stat'], cwd=crate_dir, capture_output=True, text=True)
        print(proc.stdout)
    return 0

def _finish(record, n, out_dir, report_lines, totals):
    fn_name = record.pop('fn', 'target')
    (out_dir / f'{n}_{fn_name}.json').write_text(json.dumps(record, indent=2))
    report_lines.append(json.dumps(record))
    if record['verdict'] == 'accept':
        totals['accepted'] += 1
    else:
        totals['reject_reasons'][record['reason']] = totals['reject_reasons'].get(record['reason'], 0) + 1
    print(f"[{n}] {record['target']}: {record['verdict']}"
          + (f" ({record['reason']})" if record['reason'] else ''))


if __name__ == '__main__':
    sys.exit(main())
