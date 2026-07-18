# Swar versus Wispr Flow benchmark

This benchmark measures transcription accuracy from the same reading passage. It does not send audio or transcripts anywhere.

1. Open a plain text editor and dictate `cases/english-01.txt` with Swar. Save only the inserted text as `benchmark/audio/local/swar.txt`.
2. Read the same passage in the same room and microphone with Wispr Flow. Save its inserted text as `benchmark/audio/local/wispr.txt`.
3. Record the time from stopping speech until text appears for each product.
4. Run:

```sh
./scripts/run_dictation_benchmark.sh \
  benchmark/cases/english-01.txt \
  benchmark/audio/local/swar.txt \
  benchmark/audio/local/wispr.txt \
  1200 \
  900
```

The last two values are completion latency in milliseconds. Reports are written under `benchmark/reports/generated/`, which is intentionally ignored because transcripts may be personal.

For a fair result, use Raw mode first. Clean and Intent modes intentionally rewrite speech, so word error rate alone is not a useful quality measure for them.
