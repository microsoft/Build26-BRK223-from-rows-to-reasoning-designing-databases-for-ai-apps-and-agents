import { useEffect, useRef } from 'react';
import ProductCard from './ProductCard';

export default function SuggestionsPanel({
  products,
  selectedIds,
  toggleProduct,
  priorities,
  budget,
  totalSpent,
  isDesigned,
  highlightedProductId,
  onHighlightConsumed,
}) {
  const cardRefs = useRef({});

  useEffect(() => {
    if (!highlightedProductId) return;
    const el = cardRefs.current[highlightedProductId];
    if (el) {
      el.scrollIntoView({ behavior: 'smooth', block: 'center' });
    }
    const t = setTimeout(() => onHighlightConsumed && onHighlightConsumed(), 2000);
    return () => clearTimeout(t);
  }, [highlightedProductId, onHighlightConsumed]);
  if (!isDesigned) {
    return (
      <div className="suggestions-panel empty">
        <div className="sp-empty">
          <span className="sp-empty-icon">🪄</span>
          <h3>AI picks will appear here</h3>
          <p>
            Fill out your design brief and click <strong>"Design My Room"</strong>{' '}
            to get personalized furniture suggestions.
          </p>
        </div>
      </div>
    );
  }

  const pct = Math.min((totalSpent / budget) * 100, 100);
  const isOver = totalSpent > budget;

  return (
    <div className="suggestions-panel">
      {/* Budget summary */}
      <div className="sp-budget">
        <div className="sp-budget-header">
          <h3 className="sp-budget-title">Budget Tracker</h3>
          <span className={`sp-budget-status ${isOver ? 'over' : pct > 85 ? 'warn' : 'ok'}`}>
            {isOver
              ? '⚠ Over budget'
              : pct > 85
                ? '● Almost there'
                : '● On track'}
          </span>
        </div>
        <div className="sp-budget-bar-wrap">
          <div
            className="sp-budget-bar"
            style={{
              width: `${pct}%`,
              backgroundColor: isOver
                ? 'var(--danger)'
                : pct > 85
                  ? 'var(--warning)'
                  : 'var(--success)',
            }}
          />
        </div>
        <div className="sp-budget-nums">
          <span>${totalSpent.toLocaleString('en-US', { minimumFractionDigits: 2 })}</span>
          <span>${budget.toLocaleString()}</span>
        </div>
      </div>

      {/* Item count */}
      <div className="sp-meta">
        <span className="sp-count">
          {selectedIds.size} of {products.length} items selected
        </span>
        <span className="sp-ai-badge">🤖 AI Curated</span>
      </div>

      {/* Product cards – priority items first, in rank order */}
      <div className="sp-list">
        {[...products]
          .sort((a, b) => {
            const ai = priorities.indexOf(a.category);
            const bi = priorities.indexOf(b.category);
            const ar = ai >= 0 ? ai : Infinity;
            const br = bi >= 0 ? bi : Infinity;
            return ar - br;
          })
          .map((p) => {
            const priIdx = priorities.indexOf(p.category);
            return (
              <div
                key={p.id}
                ref={(el) => { if (el) cardRefs.current[p.id] = el; }}
                className={highlightedProductId === p.id ? 'sp-card-highlight' : ''}
              >
                <ProductCard
                  product={p}
                  isSelected={selectedIds.has(p.id)}
                  onToggle={toggleProduct}
                  priorityRank={priIdx >= 0 ? priIdx : null}
                />
              </div>
            );
          })}
      </div>
    </div>
  );
}
