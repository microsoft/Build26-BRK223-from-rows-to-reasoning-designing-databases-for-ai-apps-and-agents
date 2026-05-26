# Backlog

## Mitigation Latency Evaluation (GPU + phi4-mini)

### Context
- Observed direct mitigation run time: ~124 seconds for incident 5012.
- Local models are GPU-backed (Ollama reports 100% GPU residency for phi4-mini and mxbai-embed-large).
- End-to-end latency appears dominated by chat generation step in `usp_GenerateMitigation`, not by SQL lookup/update overhead.

### Hypothesis
- GPU is active, but latency remains high due to prompt prefill size, response length, and end-to-end orchestration overhead.

### Evaluation Tasks
- Benchmark current baseline over multiple runs (e.g., 3-5) and record p50/p95 duration.
- Measure token/request size effects by reducing context payload:
  - lower top-K or shorten retrieved snippets before model call
  - trim system prompt where safe
- Cap response size for mitigation JSON (reduce max token budget).
- Compare chat model alternatives for speed/quality tradeoff (smaller/faster local model vs current phi4-mini).
- Re-test with identical incident and capture duration + output quality deltas.

### Success Criteria
- Reduce mitigation latency meaningfully (target to be agreed).
- Preserve demo-acceptable mitigation quality and structure.
- Keep workflow deterministic enough for live demo timing.
