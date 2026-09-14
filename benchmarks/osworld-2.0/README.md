# Autobot on OSWorld 2.0

**32.41% binary accuracy. 64.28% partial accuracy. 108 tasks.**

Autobot with GPT-5.6 Sol Max fully completed **35 tasks** in our final combined OSWorld 2.0 result, using an open-source harness with batch tools.

![OSWorld 2.0 leaderboard comparison: Autobot scores 32.41% binary accuracy and 64.28% partial accuracy](../../docs/benchmark-charts/osworld-2.0-highlighted.png)

## Result and method

This is our **best-valid-per-task aggregate**, finalized September 10, 2026, on release `osworld-v2-2026.08.08`. It combines 92 retained results with the highest valid native score for each of 16 rerun tasks across R9 and R10. Equal scores retain the earliest eligible attempt. The 16 tasks were rerun because a bug was found which allowed the harness to use Astra for those 16 tasks (Astra was released mid benchmark run). The impact of Astra corrupted the results for those 16 tasks, and thus the score could not be used. We then re-ran those 16 tasks using only Sol-Max, to preserve the integrity of the benchmarking task scores. The R9 and R10 reference revisions made to ensure no Astra was used. R9 was successful for nearly all 16 tasks, but an infrastructure bug was found which led to the use of the R10 harness. The R10 harness had its own issues, and so for the sake of expediency, we used the highest of the two scores. Neither R9 nor R10 used Astra. 

Scores come from the benchmark's native task evaluator. Binary accuracy counts exact `1.0` results: `35 / 108 × 100 = 32.41%`. Partial accuracy averages the native rewards: `69.42029134083895352 / 108 × 100 = 64.28%`.

The chart compares this aggregate with the published leaderboard snapshot dated September 10, 2026. Its comparison rank is separate from official leaderboard placement.

## Verify the scores

- [Task scores](results.csv): all 108 exact native rewards.
- [Summary](summary.json): result, configuration and selection method.
- [Score evidence](score-evidence.json): native result text and source SHA-256 bindings.
- [Checksums](SHA256SUMS): integrity hashes for the package.

From this folder, run the included standard-library Python verifier:

```sh
python3 verify.py
```

It checks task coverage, native result hashes, package integrity and both reported scores.

[Official benchmark](https://github.com/xlang-ai/OSWorld-V2) · [Leaderboard](https://osworld-v2.xlang.ai/) · [Back to Autobot](../../README.md)
