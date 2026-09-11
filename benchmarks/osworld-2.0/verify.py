#!/usr/bin/env python3
"""Verify this published OSWorld 2.0 score package using Python's standard library."""
import csv
import hashlib
import json
from decimal import Decimal, localcontext
from pathlib import Path

ROOT = Path(__file__).resolve().parent
FILES = {'README.md', 'leaderboard-comparison.jpg', 'results.csv',
         'score-evidence.json', 'summary.json', 'verify.py'}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def main():
    entries = [line.split('  ', 1) for line in (ROOT / 'SHA256SUMS').read_text().splitlines()]
    require(len(entries) == len(FILES) and {name for _, name in entries} == FILES,
            'Checksum manifest must cover exactly the six package files')
    for digest, name in entries:
        require(hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == digest,
                f'Package checksum mismatch: {name}')
    with (ROOT / 'results.csv').open(newline='') as stream:
        rows = list(csv.DictReader(stream))
    summary = json.loads((ROOT / 'summary.json').read_text())
    evidence = json.loads((ROOT / 'score-evidence.json').read_text())
    expected = {f'{i:03}' for i in range(1, 109)}
    require(len(rows) == 108 and {r['task_id'] for r in rows} == expected,
            'Scores must contain each task 001 through 108 exactly once')
    native = evidence['tasks']
    require(len(native) == 108 and {r['task_id'] for r in native} == expected,
            'Evidence must contain each task exactly once')
    require(evidence['source_score_seal_sha256'] == summary['source_score_seal_sha256'],
            'Source seal bindings differ')
    native = {r['task_id']: r for r in native}
    with localcontext() as context:
        context.prec = 80
        rewards = []
        for row in rows:
            source = native[row['task_id']]
            raw = source['native_result_text'].encode('utf-8')
            digest = hashlib.sha256(raw).hexdigest()
            require(digest == row['result_sha256'] == source['native_result_sha256'],
                    f'Native hash mismatch: task {row["task_id"]}')
            require(raw.decode().strip() == row['native_reward'],
                    f'Native value mismatch: task {row["task_id"]}')
            value = Decimal(row['native_reward'])
            require(value.is_finite() and Decimal(0) <= value <= Decimal(1),
                    f'Invalid reward: task {row["task_id"]}')
            rewards.append(value)
        total = sum(rewards)
        perfect = sum(value == 1 for value in rewards)
        require(summary['task_count'] == 108 and summary['fully_completed_tasks'] == perfect == 35,
                'Task counts differ')
        require(total == Decimal(summary['native_reward_sum']) == Decimal('69.42029134083895352'),
                'Native reward sum differs')
        binary, partial = Decimal(perfect) / 108 * 100, total / 108 * 100
        for metric, value in [('binary', binary), ('partial', partial)]:
            require(abs(value - Decimal(summary[metric + '_accuracy_percent'])) < Decimal('1e-60'),
                    f'{metric} summary differs')
        print(f'PASS: 108 tasks; {perfect} fully completed; '
              f'{binary:.2f}% binary accuracy; {partial:.2f}% partial accuracy.')
        print('Package checksums, exact native values and source bindings match.')


if __name__ == '__main__':
    main()
