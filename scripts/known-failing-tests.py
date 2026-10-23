#!/usr/bin/env python3
"""Run the InstantSwiftDataCoreTests bundle and keep Tests/known-failing.txt (#1021).

Before #1021 nothing written down said which of the bundle's tests fail on main, so every agent ran main's whole
bundle as a baseline before it could tell its own failures apart, doubling its test time on machines that were already
saturated. This script is the one way to run the bundle, so a run on a branch and the list compare like for like:

  scripts/known-failing-tests.sh run <out-dir> [--load N] [--jobs N] [--filter RE] [--skip RE] [--no-build]
  scripts/known-failing-tests.sh compare <out-dir>     # exits 1 when the run failed a test the list does not name
  scripts/known-failing-tests.sh failing <out-dir>     # each failing test with its first issue
  scripts/known-failing-tests.sh record <out-dir>...   # idle runs and loaded runs, in any order

`run` builds the bundle and the `instant-swift-data` executable its CLI tests launch, checks out the upstream sources
the parity tests read at the commits those tests pin, and runs every Swift Testing test with an event stream, so a
killed or hung run still says which tests finished. `--load N` runs N busy loops beside it, at the same priority, to
show which tests measure the machine rather than the code. Run it at nice 10 on a shared machine
(`nice -n 10 scripts/known-failing-tests.sh run ...`), or through the machine's heavy-job queue.

`record` writes the list from whole-bundle runs, idle ones and loaded ones: `idle k/n` names failed in k of n idle
runs, `load k/n` names never failed idle and failed in k of n loaded runs. It keeps the verdicts of names already on
the list.

History:
- 2026-10-23: written for #1021 (the list, idle and under load, and compare instead of a baseline run of main).
"""

import argparse
import datetime
import json
import os
import platform
import re
import shutil
import signal
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUNDLE = 'InstantSwiftDataCoreTests'
LIST = os.path.join(ROOT, 'Tests', 'known-failing.txt')
DEFAULT_CACHE = os.path.expanduser('~/Library/Caches/instant-data-swift-known-failing')

# The parity tests pin these checkouts; their pins are read from the tests so they are never written twice.
UPSTREAMS = [
    {
        'name': 'instant',
        'env': 'INSTANT_UPSTREAM_CHECKOUT',
        'pin_file': 'Tests/InstantSwiftDataCoreTests/InstantUpstreamParityReconciliationTests.swift',
        'url': 'https://github.com/instantdb/instant.git',
        # Only these files are read (the core tests and their fixtures, about 2 MB); the whole tree is ~600 MB.
        'sparse': '/client/packages/core/__tests__/src/',
        'probe': 'client/packages/core/__tests__/src',
    },
    {
        'name': 'sqlite-data',
        'env': 'SQLITE_DATA_UPSTREAM_CHECKOUT',
        'pin_file': 'Tests/InstantSwiftDataCoreTests/InstantSQLiteDataParityReconciliationTests.swift',
        'url': 'https://github.com/pointfreeco/sqlite-data.git',
        'sparse': None,
        'probe': 'Tests',
    },
]


def log(message):
    print(message, flush=True)


def git(args, cwd, check=True, capture=True):
    result = subprocess.run(
        ['git'] + args, cwd=cwd, check=False,
        stdout=subprocess.PIPE if capture else None, stderr=subprocess.PIPE, text=True,
    )
    if check and result.returncode != 0:
        raise SystemExit('git %s failed in %s: %s' % (' '.join(args), cwd, result.stderr.strip()))
    return result.stdout.strip() if capture else ''


def head_of(path):
    if not os.path.isdir(path):
        return None
    result = subprocess.run(['git', '-C', path, 'rev-parse', 'HEAD'], stdout=subprocess.PIPE,
                            stderr=subprocess.DEVNULL, text=True)
    return result.stdout.strip() if result.returncode == 0 else None


def pin_of(upstream):
    with open(os.path.join(ROOT, upstream['pin_file'])) as f:
        match = re.search(r'static let pinnedUpstreamCommit = "([0-9a-f]{40})"', f.read())
    if not match:
        raise SystemExit('no pinnedUpstreamCommit in %s' % upstream['pin_file'])
    return match.group(1)


def prepare_upstreams(cache):
    """Point each parity test at a checkout of its pinned commit, fetching a small sparse one when needed."""
    env = {}
    for upstream in UPSTREAMS:
        pin = pin_of(upstream)
        override = os.environ.get(upstream['env'])
        in_tree = os.path.join(ROOT, 'upstream', upstream['name'])
        candidates = ([override] if override else []) + [in_tree, os.path.join(cache, '%s-%s' % (upstream['name'], pin))]
        chosen = None
        for path in candidates:
            if head_of(path) == pin and os.path.exists(os.path.join(path, upstream['probe'])):
                chosen = path
                break
        if chosen is None:
            chosen = os.path.join(cache, '%s-%s' % (upstream['name'], pin))
            log('fetching upstream %s at %s into %s' % (upstream['name'], pin[:8], chosen))
            shutil.rmtree(chosen, ignore_errors=True)
            os.makedirs(chosen)
            git(['init', '-q'], chosen)
            git(['remote', 'add', 'origin', upstream['url']], chosen)
            fetch = ['fetch', '-q', '--depth', '1']
            if upstream['sparse']:
                git(['sparse-checkout', 'set', '--no-cone', upstream['sparse']], chosen)
                fetch.append('--filter=blob:none')
            git(fetch + ['origin', pin], chosen)
            git(['checkout', '-q', 'FETCH_HEAD'], chosen)
        env[upstream['env']] = chosen
        log('upstream %s %s: %s' % (upstream['name'], pin[:8], chosen))
    return env


def developer_dir():
    if os.environ.get('DEVELOPER_DIR'):
        return os.environ['DEVELOPER_DIR']
    return subprocess.run(['xcode-select', '-p'], stdout=subprocess.PIPE, text=True, check=True).stdout.strip()


def swift_build(args, jobs, scratch, out):
    base = ['swift', 'build', '-j', str(jobs)] + (['--scratch-path', scratch] if scratch else [])
    with open(os.path.join(out, 'build.log'), 'a') as build_log:
        for product in [BUNDLE, 'instant-swift-data']:
            started = time.time()
            log('building %s (-j %d)' % (product, jobs))
            status = subprocess.run(base + ['--product', product], cwd=ROOT, stdout=build_log,
                                    stderr=subprocess.STDOUT).returncode
            log('built %s: exit %d in %.0f s' % (product, status, time.time() - started))
            if status != 0:
                raise SystemExit('swift build --product %s failed; see %s/build.log' % (product, out))
    return subprocess.run(base + ['--show-bin-path'], cwd=ROOT, stdout=subprocess.PIPE, text=True,
                          check=True).stdout.strip()


def load_average():
    return float(subprocess.run(['sysctl', '-n', 'vm.loadavg'], stdout=subprocess.PIPE, text=True)
                 .stdout.split()[1])


def commit_and_version(options):
    """The tree under test; a copy without .git (another machine's scratch) names it with --commit and --version."""
    if options.commit:
        return options.commit, False, options.version or 'unknown'
    commit = git(['rev-parse', 'HEAD'], ROOT, check=False) or 'unknown'
    dirty = bool(git(['status', '--porcelain', '--untracked-files=no'], ROOT, check=False))
    version = git(['describe', '--tags', '--abbrev=0'], ROOT, check=False) or 'unknown'
    return commit, dirty, version


def cmd_run(options):
    out = os.path.abspath(options.out)
    os.makedirs(out, exist_ok=True)
    for name in ['console.log', 'events.jsonl', 'load.log', 'summary.json', 'failing.txt', 'sample.txt']:
        if os.path.exists(os.path.join(out, name)):
            os.remove(os.path.join(out, name))
    env = dict(os.environ)
    env.update(prepare_upstreams(os.path.abspath(options.cache)))
    if options.no_build:
        bin_path = subprocess.run(
            ['swift', 'build', '--show-bin-path'] + (['--scratch-path', options.scratch_path] if options.scratch_path else []),
            cwd=ROOT, stdout=subprocess.PIPE, text=True, check=True).stdout.strip()
    else:
        bin_path = swift_build([], options.jobs, options.scratch_path, out)
    cli = os.path.join(bin_path, 'instant-swift-data')
    if os.path.exists(cli):
        # The CLI tests launch the executable; with a custom scratch path it is not under .build.
        env['INSTANT_SWIFT_DATA_CLI_EXECUTABLE'] = cli
    bundle = os.path.join(bin_path, BUNDLE + '.xctest')
    if not os.path.isdir(bundle):
        raise SystemExit('no %s under %s; build it first' % (os.path.basename(bundle), bin_path))
    developer = developer_dir()
    platform_dir = os.path.join(developer, 'Platforms/MacOSX.platform/Developer')
    env['DYLD_LIBRARY_PATH'] = ':'.join([bin_path, os.path.join(platform_dir, 'usr/lib')])
    env['DYLD_FRAMEWORK_PATH'] = ':'.join([
        os.path.join(bin_path, 'PackageFrameworks'), bin_path,
        os.path.join(platform_dir, 'Library/Frameworks'), os.path.join(platform_dir, 'Library/PrivateFrameworks'),
    ])
    helper = os.path.join(developer, 'Toolchains/XcodeDefault.xctoolchain/usr/libexec/swift/pm/swiftpm-testing-helper')
    command = [helper, '--test-bundle-path', os.path.join(bundle, 'Contents/MacOS', BUNDLE),
               '--testing-library', 'swift-testing',
               '--event-stream-output-path', os.path.join(out, 'events.jsonl'), '--event-stream-version', '0']
    if options.filter:
        command += ['--filter', options.filter]
    if options.skip:
        command += ['--skip', options.skip]

    burners = []
    if options.load:
        log('starting %d busy loops as load' % options.load)
        for _ in range(options.load):
            burners.append(subprocess.Popen(['/usr/bin/yes'], stdout=subprocess.DEVNULL))
        time.sleep(20)
    commit, dirty, version = commit_and_version(options)
    started_at = time.time()
    loads = []
    status = None
    timed_out = False
    log('running %s (timeout %d s)' % (BUNDLE, options.timeout))
    try:
        with open(os.path.join(out, 'console.log'), 'w') as console, open(os.path.join(out, 'load.log'), 'w') as load_log:
            # The tests resolve the package and the upstream checkouts from their own source paths; run from the root anyway.
            process = subprocess.Popen(command, cwd=ROOT, env=env, stdout=console, stderr=subprocess.STDOUT)
            next_sample = 0.0
            while True:
                status = process.poll()
                now = time.time()
                if now >= next_sample:
                    value = load_average()
                    loads.append(value)
                    load_log.write('%s %.2f\n' % (datetime.datetime.now().strftime('%H:%M:%S'), value))
                    load_log.flush()
                    next_sample = now + 10
                if status is not None:
                    break
                if now - started_at > options.timeout:
                    timed_out = True
                    subprocess.run(['sample', str(process.pid), '3', '-file', os.path.join(out, 'sample.txt')],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    process.kill()
                    status = process.wait()
                    break
                time.sleep(1)
    finally:
        for burner in burners:
            burner.send_signal(signal.SIGTERM)
        for burner in burners:
            burner.wait()
    seconds = time.time() - started_at
    results = parse_events(os.path.join(out, 'events.jsonl'))
    failing = sorted(name for name, test in results['tests'].items() if test['status'] in ('failed', 'hung'))
    with open(os.path.join(out, 'failing.txt'), 'w') as f:
        for name in failing:
            f.write(name + '\n')
    summary = {
        'commit': commit, 'dirty': dirty, 'version': version, 'host': platform.node(),
        'started': datetime.datetime.fromtimestamp(started_at).astimezone().isoformat(timespec='seconds'),
        'seconds': round(seconds, 1), 'exit': status, 'timed_out': timed_out,
        'load': {'busy_loops': options.load, 'min': min(loads) if loads else None,
                 'mean': round(sum(loads) / len(loads), 1) if loads else None, 'max': max(loads) if loads else None},
        'cpus': os.cpu_count(), 'filter': options.filter, 'skip': options.skip,
        'tests': len(results['tests']), 'failing': len(failing),
        'hung': sorted(name for name, test in results['tests'].items() if test['status'] == 'hung'),
    }
    with open(os.path.join(out, 'summary.json'), 'w') as f:
        json.dump(summary, f, indent=2)
        f.write('\n')
    log('%s: %d tests, %d failing, %.0f s, load %s-%s (mean %s)%s' % (
        out, summary['tests'], summary['failing'], seconds, summary['load']['min'], summary['load']['max'],
        summary['load']['mean'], ', TIMED OUT' if timed_out else ''))
    return 0


def test_name(test_id):
    """`InstantSwiftDataCoreTests.Suite/test()/File.swift:12:4` -> `Suite/test()`: no module, no source location."""
    parts = test_id.split('/')
    if len(parts) > 1 and re.match(r'.+\.swift:\d+:\d+$', parts[-1]):
        parts = parts[:-1]
    name = '/'.join(parts)
    for prefix in (BUNDLE + '.', BUNDLE + '/'):
        if name.startswith(prefix):
            return name[len(prefix):]
    return name


def parse_events(path):
    """Each test function's outcome from a Swift Testing event stream (version 0), even a cut-short one."""
    tests = {}
    run_ended = False
    if not os.path.exists(path):
        return {'tests': tests, 'run_ended': False}
    with open(path, errors='replace') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
            except ValueError:
                continue
            payload = record.get('payload', {})
            if record.get('kind') == 'test':
                if payload.get('kind') != 'function':
                    continue
                location = payload.get('sourceLocation', {})
                tests.setdefault(test_name(payload['id']), {
                    'status': 'declared', 'display': payload.get('displayName') or payload.get('name'),
                    'file': location.get('fileID') or location.get('filePath'), 'line': location.get('line'),
                    'issues': [],
                })
                continue
            if record.get('kind') != 'event':
                continue
            kind = payload.get('kind')
            if kind == 'runEnded':
                run_ended = True
                continue
            test_id = payload.get('testID')
            if not test_id:
                continue
            test = tests.get(test_name(test_id))
            if test is None:
                continue
            if kind == 'testStarted':
                test['status'] = 'started'
            elif kind == 'testSkipped':
                test['status'] = 'skipped'
            elif kind == 'issueRecorded':
                issue = payload.get('issue', {})
                if issue.get('isKnown') or issue.get('severity', 'error') != 'error':
                    continue
                location = issue.get('sourceLocation') or {}
                messages = [m.get('text', '') for m in payload.get('messages', [])]
                test['issues'].append({
                    'at': '%s:%s' % (os.path.basename(location.get('fileID') or location.get('filePath') or '?'),
                                     location.get('line', '?')),
                    # One line, so `failing` and `compare` print one test per line.
                    'message': ' '.join(' '.join(messages).split())[:400],
                })
                # Work a test left running can record an issue after the test ended, and the console then says it
                # passed; the issue is still that test's failure.
                if test['status'] in ('passed', 'failed'):
                    test['status'] = 'failed'
                    test['issues'][-1]['message'] = '(after the test ended) ' + test['issues'][-1]['message']
            elif kind == 'testEnded':
                test['status'] = 'failed' if test['issues'] else 'passed'
    for test in tests.values():
        if test['status'] == 'started':
            test['status'] = 'hung' if not run_ended else ('failed' if test['issues'] else 'passed')
    # A declared test that never started was filtered out or skipped; it is not part of the run.
    tests = {name: test for name, test in tests.items() if test['status'] != 'declared'}
    return {'tests': tests, 'run_ended': run_ended}


def read_summary(out):
    path = os.path.join(out, 'summary.json')
    if not os.path.exists(path):
        raise SystemExit('%s has no summary.json; is it a run directory?' % out)
    with open(path) as f:
        return json.load(f)


def read_list(path):
    entries = {}
    header = []
    if not os.path.exists(path):
        return entries, header
    with open(path) as f:
        for line in f:
            line = line.rstrip('\n')
            if not line.strip():
                continue
            if line.startswith('#'):
                header.append(line)
                continue
            fields = line.split('\t')
            fields += ['-'] * (4 - len(fields))
            entries[fields[1]] = {'when': fields[0], 'last_passed': fields[2], 'verdict': fields[3]}
    return entries, header


def describe(summary):
    load = summary['load']
    return '%s, %s, %s tests, %s failing, %.0f s, %d CPUs, %s busy loops, load %s-%s%s' % (
        summary['host'], summary['started'], summary['tests'], summary['failing'], summary['seconds'],
        summary['cpus'] or 0, load['busy_loops'], load['min'], load['max'],
        ', timed out' if summary['timed_out'] else '')


def cmd_record(options):
    runs = []
    for run_dir in options.runs:
        summary = read_summary(run_dir)
        if summary['filter'] or summary['skip']:
            raise SystemExit('record wants whole-bundle runs; %s used --filter/--skip' % run_dir)
        tests = parse_events(os.path.join(run_dir, 'events.jsonl'))['tests']
        summary['failing'] = sum(1 for test in tests.values() if test['status'] in ('failed', 'hung'))
        runs.append((summary, tests))
    runs.sort(key=lambda run: run[0]['started'])
    idle_runs = [run for run in runs if not run[0]['load']['busy_loops']]
    loaded_runs = [run for run in runs if run[0]['load']['busy_loops']]
    if not idle_runs:
        raise SystemExit('record needs at least one idle run (no --load)')
    previous, _ = read_list(options.list)

    def failed(tests, name):
        return name in tests and tests[name]['status'] in ('failed', 'hung')

    names = sorted({name for _, tests in runs for name in tests if failed(tests, name)})
    lines = []
    for name in names:
        idle_count = sum(1 for _, tests in idle_runs if failed(tests, name))
        load_count = sum(1 for _, tests in loaded_runs if failed(tests, name))
        if idle_count:
            when = 'idle %d/%d' % (idle_count, len(idle_runs))
        else:
            when = 'load %d/%d' % (load_count, len(loaded_runs))
        kept = previous.get(name, {})
        last_passed = kept.get('last_passed', '-')
        passes = [summary for summary, tests in runs if name in tests and tests[name]['status'] == 'passed']
        if passes:
            # A name that passed in one of these runs last passed at that run's commit.
            last_passed = '%s %s' % (passes[-1]['version'], passes[-1]['commit'][:8])
        lines.append((0 if idle_count else 1, name, when, last_passed, kept.get('verdict', 'open')))
    lines.sort()
    header = [
        '# InstantSwiftDataCoreTests: the tests that fail on main, and when (#1021).',
        '#',
        "# Compare a run against this list instead of running main's whole bundle as a baseline:",
        '#   scripts/known-failing-tests.sh run <out-dir> [--load N] && scripts/known-failing-tests.sh compare <out-dir>',
        '# `compare` exits 1 when the run failed a test this list does not name. Written by',
        '# `scripts/known-failing-tests.sh record <run-dir>...` from whole-bundle runs; it keeps the verdicts.',
        '#',
        '# Runs it was recorded from:',
    ]
    for summary, _ in runs:
        header.append('#   %s at %s%s (%s): %s.' % (
            'loaded' if summary['load']['busy_loops'] else 'idle', summary['commit'][:8],
            ' plus uncommitted changes' if summary['dirty'] else '', summary['version'], describe(summary)))
    header += [
        '#',
        '# Columns, tab-separated: when, test, last passed, verdict.',
        '#   when: idle k/n (failed in k of n idle runs) or load k/n (never failed idle; failed in k of n loaded runs)',
        '#   last passed: the version and commit it last passed in, where known; - when not known',
        '#   verdict: what is being done about it, with its issue; open until it has one',
        '',
    ]
    with open(options.list, 'w') as f:
        f.write('\n'.join(header) + '\n')
        for _, name, when, last_passed, verdict in lines:
            f.write('\t'.join([when, name, last_passed, verdict]) + '\n')
    idle_names = sum(1 for line in lines if line[0] == 0)
    log('wrote %s: %d names, %d failed idle, %d only under load' % (
        os.path.relpath(options.list, ROOT), len(lines), idle_names, len(lines) - idle_names))
    return 0


def first_issue(test):
    if not test['issues']:
        return 'no issue recorded (%s)' % test['status']
    return '%s: %s' % (test['issues'][0]['at'], test['issues'][0]['message'])


def cmd_compare(options):
    summary = read_summary(options.out)
    tests = parse_events(os.path.join(options.out, 'events.jsonl'))['tests']
    known, _ = read_list(options.list)
    failing = {name for name, test in tests.items() if test['status'] in ('failed', 'hung')}
    summary['failing'] = len(failing)
    new = sorted(failing - set(known))
    listed_failed = sorted(failing & set(known))
    passed = [name for name in known if name in tests and name not in failing]
    idle_passed = sorted(name for name in passed if known[name]['when'].startswith('idle'))
    log('%s against %s' % (options.out, os.path.relpath(options.list, ROOT)))
    log('  run: %s' % describe(summary))
    log('  failed and listed: %d' % len(listed_failed))
    log('  listed load-only, passed: %d' % (len(passed) - len(idle_passed)))
    if idle_passed:
        log('  listed as failing idle, passed: %d (fixed, or one that fails only some runs)' % len(idle_passed))
        for name in idle_passed:
            log('    %s  [%s]' % (name, known[name]['when']))
    not_run = sorted(name for name in known if name not in tests)
    if not_run and (summary['filter'] or summary['skip']):
        log('  listed but not run (filtered): %d' % len(not_run))
    elif not_run:
        log('  listed but not in this bundle: %d (renamed or removed?)' % len(not_run))
        for name in not_run:
            log('    %s' % name)
    if summary['hung']:
        log('  hung (started, never ended): %s' % ', '.join(summary['hung']))
    if new:
        log('  NEW failures, not on the list: %d' % len(new))
        for name in new:
            log('    %s\n      %s' % (name, first_issue(tests[name])))
        return 1
    log('  no new failures')
    return 0


def cmd_failing(options):
    tests = parse_events(os.path.join(options.out, 'events.jsonl'))['tests']
    known, _ = read_list(options.list)
    for name, test in sorted(tests.items()):
        if test['status'] in ('failed', 'hung'):
            listed = known.get(name, {}).get('when', 'NEW')
            log('%s\t%s\t%s' % (listed, name, first_issue(test)))
    return 0


def main(argv):
    parser = argparse.ArgumentParser(prog='scripts/known-failing-tests.sh', description=__doc__.split('\n\n')[0])
    sub = parser.add_subparsers(dest='command', required=True)
    run = sub.add_parser('run', help='build and run the bundle into a run directory')
    run.add_argument('out')
    run.add_argument('--load', type=int, default=0, help='busy loops to run beside the bundle (try 2x the CPUs)')
    run.add_argument('--jobs', type=int, default=4, help='swift build -j (default 4)')
    run.add_argument('--scratch-path', default=None, help='swift build --scratch-path (default .build)')
    run.add_argument('--cache', default=DEFAULT_CACHE, help='where fetched upstream checkouts are kept')
    run.add_argument('--filter', default=None)
    run.add_argument('--skip', default=None)
    run.add_argument('--timeout', type=int, default=2400, help='kill the run after this many seconds (default 2400)')
    run.add_argument('--no-build', action='store_true', help='run what is already built')
    run.add_argument('--commit', default=None, help='the commit a copy without .git was exported from')
    run.add_argument('--version', default=None, help='the release that commit belongs to, with --commit')
    record = sub.add_parser('record', help='write the list from idle and loaded whole-bundle runs')
    record.add_argument('runs', nargs='+')
    record.add_argument('--list', default=LIST)
    compare = sub.add_parser('compare', help='compare a run with the list; exit 1 on a new failure')
    compare.add_argument('out')
    compare.add_argument('--list', default=LIST)
    failing = sub.add_parser('failing', help="a run's failing tests with their first issue")
    failing.add_argument('out')
    failing.add_argument('--list', default=LIST)
    options = parser.parse_args(argv)
    return {'run': cmd_run, 'record': cmd_record, 'compare': cmd_compare, 'failing': cmd_failing}[options.command](options)


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
