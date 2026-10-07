#!/usr/bin/env python3
"""Replay cached PRs in an isolated optimized test host; report CPU/run-loop timing."""
import argparse
import pathlib
import plistlib
import shutil
import subprocess
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--products', required=True, type=pathlib.Path, help='Build/Products from build-for-testing')
parser.add_argument('--snapshot', required=True, type=pathlib.Path, help='Read-only input snapshot-v1.json')
parser.add_argument('--output', required=True, type=pathlib.Path, help='New private output directory outside the repository')
parser.add_argument('--trace', action='store_true', help='Attach Time Profiler during the replay')
args = parser.parse_args()
args.products = args.products.resolve()
args.output.mkdir(mode=0o700, parents=True, exist_ok=False)
args.output = args.output.resolve()
run_file = next(p for p in args.products.glob('*.xctestrun') if not p.name.startswith('profile-'))
run = plistlib.loads(run_file.read_bytes())
copy = args.output / 'cache.json'
report = args.output / 'report.json'
ready = pathlib.Path(str(report) + '.ready')
shutil.copyfile(args.snapshot, copy)
copy.chmod(0o600)

def configure(node):
    if isinstance(node, dict):
        if 'TestBundlePath' in node:
            node.setdefault('EnvironmentVariables', {}).update(
                PRHARBOR_TESTING='1', PRHARBOR_PROFILE_SCROLL='1',
                PRHARBOR_PROFILE_INPUT=str(copy), PRHARBOR_PROFILE_OUTPUT=str(report))
            # Resolve macros before placing the customized run outside Products.
            for key in ['TestHostPath', 'TestBundlePath']:
                if key in node:
                    node[key] = node[key].replace('__TESTROOT__', str(args.products))
            node['TestBundlePath'] = node['TestBundlePath'].replace('__TESTHOST__', node['TestHostPath'])
        else:
            for child in node.values():
                configure(child)
    elif isinstance(node, list):
        for child in node:
            configure(child)

def resolve_paths(node, host=''):
    if isinstance(node, dict):
        host = node.get('TestHostPath', host)
        return {key: resolve_paths(value, host) for key, value in node.items()}
    if isinstance(node, list):
        return [resolve_paths(value, host) for value in node]
    if isinstance(node, str):
        return node.replace('__TESTROOT__', str(args.products)).replace('__TESTHOST__', host)
    return node

configure(run)
run = resolve_paths(run)
custom = args.output / 'profile.xctestrun'
custom.write_bytes(plistlib.dumps(run))
test = None
try:
    with (args.output / 'test.log').open('w') as log:
        test = subprocess.Popen(['xcodebuild', 'test-without-building', '-xctestrun', str(custom),
            '-destination', 'platform=macOS',
            '-only-testing:PRHarborTests/NativeScrollingTests/profileCachedPullsWithDeferredRowPreparation()'],
            stdout=log, stderr=subprocess.STDOUT)
        deadline = time.monotonic() + 80
        while not ready.exists() and time.monotonic() < deadline and test.poll() is None:
            time.sleep(.2)
        if not ready.exists():
            raise RuntimeError('Replay did not start; inspect test.log')
        if args.trace:
            pid = ready.read_text().strip()
            with (args.output / 'trace.log').open('w') as trace_log:
                subprocess.run(['xcrun', 'xctrace', 'record', '--template', 'Time Profiler',
                    '--attach', pid, '--time-limit', '25s', '--output', str(args.output / 'cpu.trace')],
                    stdout=trace_log, stderr=subprocess.STDOUT, timeout=90, check=True)
        status = test.wait(timeout=100)
        if status or not report.exists():
            raise RuntimeError('Replay failed; inspect test.log')
        print(report.read_text())
finally:
    if test is not None and test.poll() is None:
        test.terminate()
        try:
            test.wait(timeout=10)
        except subprocess.TimeoutExpired:
            test.kill()
            test.wait()
    copy.unlink(missing_ok=True)
    ready.unlink(missing_ok=True)
