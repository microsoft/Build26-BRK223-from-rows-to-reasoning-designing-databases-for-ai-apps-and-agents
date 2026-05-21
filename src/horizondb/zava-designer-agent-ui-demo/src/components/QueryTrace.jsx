import { useState, useEffect } from 'react';

const PIPELINE_STEPS = [
  {
    icon: '📦',
    label: 'Data Ingestion → AI Pipelines',
    detail: '100K products ingested, embedded, and indexed automatically — durable, resumable, incremental',
    engine: 'Durable AI Pipelines — in HorizonDB',
    latency: 'pre-built',
  },
  {
    icon: '🧬',
    label: 'Room Description → Embedding',
    detail: 'Your room description embedded into a 1536-dim vector',
    engine: 'azure_openai.create_embeddings() — in HorizonDB',
    latency: '80ms',
  },
  {
    icon: '🔍',
    label: 'Hybrid Search (Vector + Full-Text + Advanced Filtering)',
    detail: 'Filtered vector search with DiskANN + pg_fts BM25 ranking — price, category, and rating filters pushed into the index scan. Advanced filtering means fewer candidates, faster results.',
    engine: 'pgvector + DiskANN + pg_fts — in HorizonDB',
    latency: '45ms',
  },
  {
    icon: '🕸️',
    label: 'Graph Traversal',
    detail: 'Style graph traverses Product → Style → SIMILAR_TO → Style to discover cross-category matches you\'d never find with a filter',
    engine: 'Apache AGE (Cypher) — in HorizonDB',
    latency: '12ms',
  },
  {
    icon: '🎯',
    label: 'AI Reranking',
    detail: 'Cohere reranks candidates for aesthetic match to your room',
    engine: 'azure_ai.rerank() — in HorizonDB',
    latency: '350ms',
  },
  {
    icon: '✅',
    label: '7 Products Returned',
    detail: 'Ranked, priced, with images — ready for your room',
    engine: 'One SQL query. One database.',
    latency: '',
  },
];

export default function QueryTrace({ isVisible, onClose }) {
  const [revealedCount, setRevealedCount] = useState(0);

  useEffect(() => {
    if (!isVisible) {
      setRevealedCount(0);
      return;
    }
    if (revealedCount >= PIPELINE_STEPS.length) return;
    const timer = setTimeout(
      () => setRevealedCount((c) => c + 1),
      revealedCount === 0 ? 300 : 400,
    );
    return () => clearTimeout(timer);
  }, [isVisible, revealedCount]);

  if (!isVisible) return null;

  return (
    <div className="query-trace-overlay" onClick={onClose}>
      <div className="query-trace-panel" onClick={(e) => e.stopPropagation()}>
        <div className="qt-header">
          <button className="qt-close" onClick={onClose} title="Close">✕</button>
          <div className="qt-header-left">
            <span className="qt-db-badge">🐘 HorizonDB</span>
            <h3 className="qt-title">What just happened — under the hood</h3>
          </div>
          <span className="qt-subtitle">
            Every step ran inside one PostgreSQL database
          </span>
        </div>

        <div className="qt-pipeline">
          {PIPELINE_STEPS.map((step, i) => {
            const isRevealed = i < revealedCount;
            const isLast = i === PIPELINE_STEPS.length - 1;
            return (
              <div
                key={i}
                className={`qt-step ${isRevealed ? 'revealed' : ''} ${isLast ? 'qt-step-final' : ''}`}
              >
                {!isLast && <div className="qt-connector" />}
                <div className="qt-step-icon">{step.icon}</div>
                <div className="qt-step-content">
                  <div className="qt-step-row">
                    <span className="qt-step-label">{step.label}</span>
                  </div>
                  <span className="qt-step-detail">{step.detail}</span>
                  <span className="qt-step-engine">{step.engine}</span>
                </div>
              </div>
            );
          })}
        </div>

        <div className={`qt-footer ${revealedCount >= PIPELINE_STEPS.length ? 'revealed' : ''}`}>
          <div className="qt-footer-stat">
            <span className="qt-footer-number">6</span>
            <span className="qt-footer-label">AI operations</span>
          </div>
          <div className="qt-footer-divider" />
          <div className="qt-footer-stat">
            <span className="qt-footer-number">1</span>
            <span className="qt-footer-label">database</span>
          </div>
          <div className="qt-footer-divider" />
          <div className="qt-footer-stat">
            <span className="qt-footer-number">1</span>
            <span className="qt-footer-label">SQL query</span>
          </div>
          <div className="qt-footer-divider" />
          <div className="qt-footer-stat">
            <span className="qt-footer-number">0</span>
            <span className="qt-footer-label">external services</span>
          </div>
        </div>
      </div>
    </div>
  );
}
