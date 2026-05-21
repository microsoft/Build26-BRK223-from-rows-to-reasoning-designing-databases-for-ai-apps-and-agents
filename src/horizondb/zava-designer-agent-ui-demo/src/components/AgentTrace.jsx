import { useState, useEffect } from 'react';

const FAKE_TOOL_CALLS = [
  {
    tool: 'analyze_room_photo',
    status: 'success',
    duration: 1200,
    sql: `SELECT azure_ai.generate(\n  'Analyze this living room photo...'\n) AS result;`,
    input: { image: 'room.jpg', detect: ['furniture', 'style', 'colors'] },
    output: {
      style: 'mid-century modern',
      colors: ['warm brown', 'cream', 'brick red'],
      existing: ['chevron sofa', 'brick wall', 'hardwood floor'],
      gaps: ['coffee table', 'accent chair', 'lighting', 'rug', 'shelving'],
    },
  },
  {
    tool: 'get_semantic_context',
    status: 'success',
    duration: 80,
    sql: `SELECT a.attname, col_description(a.attrelid, a.attnum)\nFROM pg_attribute a\nJOIN pg_class c ON a.attrelid = c.oid\nWHERE c.relname = 'product_metadata_demo';`,
    input: { term: 'mid-century modern living room' },
    output: {
      expanded_terms: ['danish modern', 'retro furniture', 'tapered legs'],
      filter_hint: 'average_rating >= 4.0',
    },
  },
  {
    tool: 'hybrid_search_products',
    status: 'success',
    duration: 1000,
    sql: `SELECT p.title, p.price, s.score\nFROM ai.search(\n  'mid-century modern furniture for Brooklyn loft',\n  source_table => 'product_metadata_demo',\n  filter => 'categories @> ''["Chairs"]'''\n) s\nJOIN product_metadata_demo p ON p.id = s.id;`,
    input: { query: 'mid-century coffee table accent chair warm lighting bohemian rug', top_k: 20, rerank: true },
    output: { results: 20, method: 'ai.search() — pg_fts BM25 + pgvector DiskANN + RRF' },
  },
  {
    tool: 'find_related_products',
    status: 'success',
    duration: 400,
    sql: `SELECT * FROM cypher('style_graph', $$\n  MATCH (seed:Product {id: 10414})-[:HAS_STYLE]->(s:Style)\n        -[:SIMILAR_TO]->(related:Style)<-[:HAS_STYLE]-(rec:Product)\n  RETURN rec.id, rec.title, related.name\n  LIMIT 5\n$$) AS (id agtype, title agtype, style agtype);`,
    input: { product_id: 10414, relationship: 'style_graph traversal' },
    output: { related: ['art-leon-chair', 'hugoai-lamp', 'safavieh-rug'] },
  },
  {
    tool: 'filter_products',
    status: 'success',
    duration: 45,
    sql: `SELECT id, title, price, average_rating\nFROM product_metadata_demo\nWHERE id = ANY($1)\n  AND price_num <= $2\n  AND average_rating >= 4.0\nORDER BY average_rating DESC;`,
    input: { max_price: 300, min_rating: 4.0, candidates: 20 },
    output: { matched: 14, filtered_out: 6 },
  },
  {
    tool: 'curate_room_picks',
    status: 'success',
    duration: 1500,
    sql: `SELECT id, rank, score\nFROM azure_ai.rank(\n  'mid-century modern furniture for Brooklyn loft',\n  $1::text[],  -- product titles\n  $2::int[]    -- product ids\n)\nORDER BY rank;`,
    input: { candidates: 14, room_style: 'mid-century modern', budget: 2000 },
    output: { final_picks: 7, total_cost: 624.37, budget_utilization: '31%' },
  },
];

export default function AgentTrace({ isVisible, onClose, traceData }) {
  const [revealedCount, setRevealedCount] = useState(0);
  const [expandedIdx, setExpandedIdx] = useState(null);

  // Use real trace data if available, otherwise fall back to fake
  const toolCalls = traceData || FAKE_TOOL_CALLS;

  useEffect(() => {
    if (!isVisible) {
      setRevealedCount(0);
      setExpandedIdx(null);
      return;
    }
    if (revealedCount >= toolCalls.length) return;
    const timer = setTimeout(
      () => setRevealedCount((c) => c + 1),
      revealedCount === 0 ? 300 : 350,
    );
    return () => clearTimeout(timer);
  }, [isVisible, revealedCount, toolCalls.length]);

  if (!isVisible) return null;

  const totalMs = toolCalls.reduce(
    (s, t) => s + (typeof t.duration === 'number' ? t.duration : parseInt(t.duration)),
    0,
  );

  return (
    <div className="agent-trace-overlay" onClick={onClose}>
      <div className="agent-trace-panel" onClick={(e) => e.stopPropagation()}>
        <div className="at-header">
          <button className="at-close" onClick={onClose} title="Close">
            ✕
          </button>
          <div className="at-header-left">
            <span className="at-badge">🤖 Agent Trace</span>
            <h3 className="at-title">Tools used to design your room</h3>
          </div>
          <span className="at-subtitle">
            {toolCalls.length} tool calls · {totalMs}ms total
            {traceData && <span className="at-live-badge"> · LIVE</span>}
          </span>
        </div>

        <div className="at-tools">
          {toolCalls.map((call, i) => {
            const isRevealed = i < revealedCount;
            const isExpanded = expandedIdx === i;
            const durationStr = typeof call.duration === 'number' ? `${call.duration}ms` : call.duration;
            return (
              <div
                key={i}
                className={`at-tool ${isRevealed ? 'revealed' : ''}`}
                onClick={() => setExpandedIdx(isExpanded ? null : i)}
              >
                <div className="at-tool-header">
                  <span className="at-tool-status">✓</span>
                  <code className="at-tool-name">{call.tool}</code>
                  <span className="at-tool-duration">{durationStr}</span>
                  <span className={`at-tool-chevron ${isExpanded ? 'open' : ''}`}>▸</span>
                </div>
                {isExpanded && (
                  <div className="at-tool-details">
                    {call.sql && (
                      <div className="at-detail-section">
                        <span className="at-detail-label">SQL</span>
                        <pre className="at-detail-sql">
                          {call.sql}
                        </pre>
                      </div>
                    )}
                    <div className="at-detail-section">
                      <span className="at-detail-label">Input</span>
                      <pre className="at-detail-json">
                        {JSON.stringify(call.input, null, 2)}
                      </pre>
                    </div>
                    <div className="at-detail-section">
                      <span className="at-detail-label">Output</span>
                      <pre className="at-detail-json">
                        {JSON.stringify(call.output, null, 2)}
                      </pre>
                    </div>
                  </div>
                )}
              </div>
            );
          })}
        </div>

        <div
          className={`at-footer ${revealedCount >= toolCalls.length ? 'revealed' : ''}`}
        >
          <div className="at-footer-stat">
            <span className="at-footer-number">{toolCalls.length}</span>
            <span className="at-footer-label">tool calls</span>
          </div>
          <div className="at-footer-divider" />
          <div className="at-footer-stat">
            <span className="at-footer-number">{totalMs}ms</span>
            <span className="at-footer-label">total latency</span>
          </div>
          <div className="at-footer-divider" />
          <div className="at-footer-stat">
            <span className="at-footer-number">0</span>
            <span className="at-footer-label">external APIs</span>
          </div>
        </div>
      </div>
    </div>
  );
}
