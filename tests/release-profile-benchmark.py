#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Compare release compiler profiles without changing Cargo.toml or live state."""
import argparse
import csv
import gzip
import hashlib
import json
import os
from pathlib import Path
import random
import re
import statistics
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
BASE_PROFILE = {
    "OPT_LEVEL": "3", "DEBUG": "false", "STRIP": "none",
    "DEBUG_ASSERTIONS": "false", "OVERFLOW_CHECKS": "false",
    "LTO": "false", "PANIC": "unwind", "INCREMENTAL": "false",
    "CODEGEN_UNITS": "16",
}
VARIANTS = {
    'baseline': {},
    'strip': {'STRIP': 'symbols'},
    'cgu1': {'STRIP': 'symbols', 'CODEGEN_UNITS': '1'},
    'thin': {'STRIP': 'symbols', 'LTO': 'thin'},
    'thin1': {'STRIP': 'symbols', 'LTO': 'thin', 'CODEGEN_UNITS': '1'},
    'fat1': {'STRIP': 'symbols', 'LTO': 'fat', 'CODEGEN_UNITS': '1'},
    'size_s': {'STRIP': 'symbols', 'LTO': 'thin', 'CODEGEN_UNITS': '1', 'OPT_LEVEL': 's'},
    'size_z': {'STRIP': 'symbols', 'LTO': 'thin', 'CODEGEN_UNITS': '1', 'OPT_LEVEL': 'z'},
    'abort': {'STRIP': 'symbols', 'LTO': 'thin', 'CODEGEN_UNITS': '1', 'PANIC': 'abort'},
}


def execute(command, env, log):
    with log.open('w') as stream:
        subprocess.run(command, cwd=ROOT, env=env, stdout=stream,
                       stderr=subprocess.STDOUT, check=True)


def environment():
    env = {k: v for k, v in os.environ.items()
           if not k.startswith(('CARGO_PROFILE_', 'OMAZEN_'))
           and k not in ('RUSTFLAGS', 'CARGO_ENCODED_RUSTFLAGS', 'CARGO_BUILD_RUSTFLAGS')}
    env['CARGO_NET_OFFLINE'] = 'true'
    return env


def binary(work, name):
    return work / 'targets' / name / 'release' / 'omazen-rust'


def fixture(work):
    base = work / 'fixture'
    home, program, config, state = [base / p for p in ('home', 'program', 'zen', 'state')]
    for path in (home, program / 'defaults/pref', config / 'one', config / 'two', state):
        path.mkdir(parents=True, exist_ok=True)
    validated = re.search(r'Some\("([^\"]+)"\) => report.pass\("Zen',
                          (ROOT / 'crates/omazen-cli/src/main.rs').read_text())
    if not validated:
        raise RuntimeError('Cannot detect the doctor validated Zen version')
    (program / 'application.ini').write_text(f'[App]\nVersion={validated[1]}\n')
    (config / 'profiles.ini').write_text(
        '[Profile0]\nName=One\nIsRelative=1\nPath=one\nDefault=1\n'
        '[Profile1]\nName=Two\nIsRelative=1\nPath=two\n')
    colors = base / 'colors.toml'
    colors.write_text('mode="dark"\naccent="#89b4fa"\nselection="#45475a"\n'
                      'muted="#6c7086"\nbackground="#1e1e2e"\ndark_background="#181825"\n'
                      'lighter_background="#313244"\nforeground="#cdd6f4"\n')
    os_release = base / 'os-release'
    os_release.write_text('ID=omarchy\nNAME=Omarchy\nVERSION_ID=4.0.6\n')
    env = environment()
    env.update(OMAZEN_TESTING='1', OMAZEN_SKIP_PACKAGE_CHECK='1',
               OMAZEN_HOME_DIR=str(home), OMAZEN_STATE_DIR=str(state),
               OMAZEN_ZEN_CONFIG_DIR=str(config), OMAZEN_ZEN_PROGRAM_DIR=str(program),
               OMAZEN_HOOKS_DIR=str(base / 'hooks'), OMAZEN_ACTIVE_COLORS=str(colors),
               OMAZEN_OS_RELEASE_FILE=str(os_release), OMAZEN_ROOT=str(ROOT),
               OMAZEN_DATA_DIR=str(base / 'data'), OMAZEN_LOCAL_BIN_DIR=str(base / 'bin'))
    execute([str(binary(work, 'baseline')), 'setup'], env, work / 'fixture-setup.txt')
    version = (ROOT / 'VERSION').read_text().strip()
    stamp = time.strftime('%Y-%m-%dT%H:%M:%S.000Z', time.gmtime())
    (state / 'bridge.log').write_text(
        f'{stamp} [INFO] BRIDGE_LOADED version={version}\n'
        f'{stamp} [INFO] PALETTE_APPLIED accent=#89b4fa mode=dark\n'
        f'{stamp} [INFO] CHROME_CSS_APPLIED primary=#89b4fa\n'
        f'{stamp} [INFO] WATCHER_READY backend=inotify\n')
    return env


def measure(command, env):
    if command[1] == 'report':
        Path(command[-1]).unlink(missing_ok=True)
    start = time.perf_counter_ns()
    child = subprocess.Popen(command, env=env, stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL)
    _, status, usage = os.wait4(child.pid, 0)
    child.returncode = os.waitstatus_to_exitcode(status)
    elapsed = time.perf_counter_ns() - start
    if child.returncode:
        raise RuntimeError(f'{command} exited {child.returncode}')
    return elapsed, round((usage.ru_utime + usage.ru_stime) * 1e9)


def percentile(values, fraction):
    values = sorted(values)
    position = (len(values) - 1) * fraction
    lower = int(position)
    upper = min(lower + 1, len(values) - 1)
    return values[lower] + (values[upper] - values[lower]) * (position - lower)


def summarize(output):
    with (output / 'samples.csv').open() as stream:
        samples = list(csv.DictReader(stream))
    groups = {}
    for row in samples:
        groups.setdefault((row['variant'], row['scenario']), []).append(row)
    records = []
    rng = random.Random(20261030)
    for (variant, scenario), rows in sorted(groups.items()):
        record = dict(variant=variant, scenario=scenario, samples=len(rows))
        for metric in ('wall_ns', 'cpu_ns'):
            values = [int(row[metric]) / 1e6 for row in rows]
            record[metric] = dict(mean_ms=statistics.mean(values), median_ms=statistics.median(values),
                                  p95_ms=percentile(values, .95), p99_ms=percentile(values, .99))
            paired_effects = []
            baseline = groups['baseline', scenario]
            for round_id in sorted({row['round'] for row in rows}):
                control = statistics.median(int(row[metric]) for row in baseline if row['round'] == round_id)
                candidate = statistics.median(int(row[metric]) for row in rows if row['round'] == round_id)
                paired_effects.append((candidate / control - 1) * 100)
            resamples = [statistics.mean(rng.choices(paired_effects, k=len(paired_effects)))
                         for _ in range(5000)]
            record[metric]['paired_round_change_percent'] = statistics.mean(paired_effects)
            record[metric]['paired_round_change_ci95'] = [percentile(resamples, .025), percentile(resamples, .975)]
        records.append(record)
    (output / 'summary.json').write_text(json.dumps(records, indent=2) + '\n')
    for record in records:
        metric = record['wall_ns']
        print(f'{record["variant"]:9} {record["scenario"]:6} median={metric["median_ms"]:.3f}ms '
              f'p95={metric["p95_ms"]:.3f}ms change={metric["paired_round_change_percent"]:+.1f}% '
              f'CI={metric["paired_round_change_ci95"]}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('phase', choices=['build', 'contracts', 'bench', 'summarize'])
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--variants', nargs='+', choices=VARIANTS, default=list(VARIANTS))
    parser.add_argument('--rounds', type=int, default=12)
    parser.add_argument('--samples', type=int, default=25)
    parser.add_argument('--report-samples', type=int, default=2)
    parser.add_argument('--scenarios', nargs='+',
                        choices=['help', 'sync', 'status', 'doctor', 'report'],
                        default=['help', 'sync', 'status', 'doctor', 'report'])
    parser.add_argument('--seed', type=int, default=20261030)
    parser.add_argument('--cpu', type=int, default=0)
    args = parser.parse_args()
    work, output = args.work.resolve(), args.output.resolve()
    work.mkdir(parents=True, exist_ok=True)
    output.mkdir(parents=True, exist_ok=True)
    if args.phase == 'summarize':
        summarize(output)
    elif args.phase == 'build':
        records = []
        for name in args.variants:
            target = work / 'targets' / name
            if target.exists():
                raise RuntimeError(f'Use an empty build directory: {target}')
            env = environment()
            env['CARGO_TARGET_DIR'] = str(target)
            settings = BASE_PROFILE | VARIANTS[name]
            env.update({f'CARGO_PROFILE_RELEASE_{k}': v for k, v in settings.items()})
            started = time.perf_counter()
            execute(['cargo', 'build', '--release', '--locked'], env, output / f'build-{name}.txt')
            seconds = time.perf_counter() - started
            data = binary(work, name).read_bytes()
            records.append(dict(variant=name, overrides=VARIANTS[name], build_seconds=seconds,
                                bytes=len(data), gzip_bytes=len(gzip.compress(data, compresslevel=6, mtime=0)),
                                sha256=hashlib.sha256(data).hexdigest()))
            (output / 'builds.json').write_text(json.dumps(records, indent=2) + '\n')
            print(f'{name}: {len(data)} bytes, clean build {seconds:.2f}s', flush=True)
        metadata = dict(commit=subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
                        source_diff_sha256=hashlib.sha256(subprocess.check_output(['git', 'diff'])).hexdigest(),
                        rustc=subprocess.check_output(['rustc', '-vV'], text=True),
                        cargo=subprocess.check_output(['cargo', '--version'], text=True).strip(),
                        cpuinfo=Path('/proc/cpuinfo').read_text().split('\n\n')[0],
                        kernel=os.uname().release, load_average=os.getloadavg(),
                        governor=Path('/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor').read_text().strip(),
                        note='Dirty working tree, same source for all variants. Clean target directories; warm dependency cache. No target-cpu=native.')
        (output / 'environment.json').write_text(json.dumps(metadata, indent=2) + '\n')
    elif args.phase == 'contracts':
        for name in args.variants:
            env = environment()
            env['OMAZEN_CANDIDATE_BIN'] = str(binary(work, name))
            for script in ('sync-contract.sh', 'read-only-contract.sh', 'state-contract.sh'):
                execute([str(ROOT / 'tests' / script)], env, output / f'{name}-{script}.txt')
            print(f'{name}: all 26 CLI contracts passed', flush=True)
    else:
        env = fixture(work)
        os.sched_setaffinity(0, {args.cpu})
        report = work / 'fixture' / 'report.tar.gz'
        scenarios = {'help': ['help'], 'sync': ['sync'], 'status': ['status'],
                     'doctor': ['doctor', '--json'], 'report': ['report', '--output', str(report)]}
        scenarios = {name: command for name, command in scenarios.items() if name in args.scenarios}
        for name in args.variants:
            result = subprocess.run([str(binary(work, name)), 'doctor', '--json'], env=env,
                                    capture_output=True, text=True, check=True)
            diagnostic = json.loads(result.stdout)
            if diagnostic['failures'] or diagnostic['warnings']:
                raise RuntimeError(diagnostic)
            for scenario, command in scenarios.items():
                for _ in range(2 if scenario == 'report' else 8):
                    measure([str(binary(work, name)), *command], env)
            print(f'{name}: warm-up complete', flush=True)
        rng = random.Random(args.seed)
        with (output / 'samples.csv').open('w', newline='') as stream:
            writer = csv.writer(stream)
            writer.writerow(['variant', 'scenario', 'round', 'sample', 'wall_ns', 'cpu_ns'])
            for round_id in range(args.rounds):
                conditions = [(name, scenario) for name in args.variants for scenario in scenarios]
                rng.shuffle(conditions)
                for name, scenario in conditions:
                    count = args.report_samples if scenario == 'report' else args.samples
                    for sample in range(count):
                        wall, cpu = measure([str(binary(work, name)), *scenarios[scenario]], env)
                        writer.writerow([name, scenario, round_id, sample, wall, cpu])
                    stream.flush()
                print(f'round {round_id + 1}/{args.rounds} complete', flush=True)
        (output / 'method.json').write_text(json.dumps(dict(rounds=args.rounds, samples=args.samples,
            report_samples_per_round=args.report_samples,
            seed=args.seed, cpu=args.cpu, variants=args.variants, warmups=8, report_warmups=2,
            scenarios=scenarios, load_average_at_end=os.getloadavg(),
            timing='perf_counter_ns around Popen + wait4; direct exec, no shell; wait4 child CPU includes report descendants; warm page cache'), indent=2) + '\n')


if __name__ == '__main__':
    main()
