import { useState, useEffect } from 'react';
import { categoryColors, categoryIcons } from '../data/mockData';

const ROOM_PHOTO = '/room-empty.jpg';
const ROOM_FURNISHED_PHOTO = '/room-furnished.jpg';

const LOADING_STEPS = [
  { icon: '📷', label: 'Analyzing room photo…', tool: 'analyze_room_photo' },
  { icon: '🧠', label: 'Understanding your style…', tool: 'get_semantic_context' },
  { icon: '🔍', label: 'Searching 100K products…', tool: 'hybrid_search_products' },
  { icon: '💰', label: 'Applying budget filters…', tool: 'filter_products' },
  { icon: '🕸️', label: 'Finding pieces that pair well…', tool: 'find_related_products' },
  { icon: '🎯', label: 'Curating room picks…', tool: 'curate_room_picks' },
];

export default function RoomView({ selectedProducts, isDesigned, isDesigning, onDesignMyRoom, onRedesign, designStep, onProductDotClick }) {
  // Progressive blur: ramps from 0 → ~18px as the agent advances through the 6 tool steps
  const blurAmount = isDesigning
    ? Math.min(18, (designStep / LOADING_STEPS.length) * 18 + 2)
    : 0;
  const blurScale = isDesigning
    ? Math.min(0.04, (designStep / LOADING_STEPS.length) * 0.04 + 0.005)
    : 0;

  return (
    <div className="room-view">
      {/* Room photo background */}
      <div className="room-scene room-scene--photo">
        <img
          src={ROOM_PHOTO}
          alt="Brooklyn apartment living room"
          className={`room-photo ${isDesigning ? 'room-photo-designing' : ''} ${isDesigned ? 'room-photo-hide' : ''}`}
          style={isDesigning ? { '--blur-amount': `${blurAmount}px`, '--blur-scale': blurScale } : undefined}
        />
        {isDesigned && (
          <img
            src={ROOM_FURNISHED_PHOTO}
            alt="Furnished Brooklyn living room"
            className="room-photo room-photo-furnished"
            onError={(e) => { e.target.style.display = 'none'; }}
          />
        )}

        {/* Floating product indicators when designed */}
        {isDesigned && selectedProducts.length > 0 && (
          <div className="room-product-overlay">
          {(() => {
            const categoryCounts = {};
            return sortProductsByCategory(selectedProducts).map((p, i) => {
              const pos = getProductPosition(p, categoryCounts, i);
              const topPct = parseFloat(pos?.top);
              const leftPct = parseFloat(pos?.left);
              const flipBelow = topPct < 45;
              const alignRight = leftPct < 25;
              const alignLeft = leftPct > 75;
              const cls = [
                'room-product-dot',
                flipBelow && 'tooltip-below',
                alignRight && 'tooltip-right',
                alignLeft && 'tooltip-left',
              ].filter(Boolean).join(' ');
              return (
              <div
                key={p.id}
                className={cls}
                style={{
                  '--dot-color': categoryColors[p.category],
                  '--dot-delay': `${i * 0.1}s`,
                  top: pos?.top,
                  left: pos?.left,
                }}
                title={p.name}
                onClick={() => onProductDotClick && onProductDotClick(p.id)}
                role="button"
                tabIndex={0}
                onKeyDown={(e) => {
                  if ((e.key === 'Enter' || e.key === ' ') && onProductDotClick) {
                    e.preventDefault();
                    onProductDotClick(p.id);
                  }
                }}
              >
                <span className="room-dot-icon">{categoryIcons[p.category]}</span>
                <div className="room-dot-tooltip">
                  {p.image && <img src={p.image} alt={p.name} className="room-dot-img" />}
                  <div className="room-dot-details">
                    <span className="room-dot-brand">{p.brand}</span>
                    <span className="room-dot-name">{p.name}</span>
                    <div className="room-dot-meta">
                      <span className="room-dot-price">${p.price.toFixed(2)}</span>
                      <span className="room-dot-rating">{'★'.repeat(Math.round(p.rating))} {Number(p.rating).toFixed(2)}</span>
                    </div>
                    <span className="room-dot-reason">{p.reason}</span>
                  </div>
                </div>
              </div>
              );
            });
          })()}
          </div>
        )}

        {/* Center label */}
        <div className={`room-label ${isDesigning ? 'room-label-designing' : ''}`}>
          {isDesigned ? (
            <>
              <span className="room-label-icon">✨</span>
              <span className="room-label-text">Your Brooklyn Living Room</span>
              <span className="room-label-sub">
                {selectedProducts.length} items placed · Mid-Century Modern
              </span>
              <button className="redesign-btn" onClick={onRedesign}>
                🔄 Redesign
              </button>
            </>
          ) : isDesigning ? (
            <div className="design-loading">
              <span className="design-loading-title">✨ Designing your room</span>
              <div className="design-loading-steps">
                {LOADING_STEPS.map((step, i) => {
                  const isDone = i < designStep;
                  const isActive = i === designStep;
                  return (
                    <div
                      key={i}
                      className={`design-step ${isDone ? 'done' : ''} ${isActive ? 'active' : ''}`}
                    >
                      <span className="design-step-icon">{isDone ? '✓' : step.icon}</span>
                      <span className="design-step-label">{step.label}</span>
                      <code className="design-step-tool">{step.tool}</code>
                    </div>
                  );
                })}
              </div>
            </div>
          ) : (
            <>
              <span className="room-label-icon">📐</span>
              <span className="room-label-text">Your empty Brooklyn loft</span>
              <span className="room-label-sub">
                Upload a photo, then let Zava Designer Agent find the perfect pieces
              </span>
              <button className="design-my-room-btn" onClick={onDesignMyRoom}>
                <span className="design-btn-sparkle">✨</span>
                Design My Room
              </button>
            </>
          )}
        </div>
      </div>
    </div>
  );
}

/*
 * Category-based positions — ensures each icon lands on the correct spot
 * regardless of the order products come back from the API.
 * Categories with multiple picks (e.g. storage) list positions in order.
 */
const CATEGORY_POSITIONS = {
  tables:   [{ top: '65%', left: '48%' }],   // Coffee Table — marble/gold, center floor
  seating:  [{ top: '52%', left: '82%' }],   // Accent Chair — white DHP chair, right side
  lighting: [{ top: '63%', left: '60%' }],   // LED Lamp — on coffee table, middle-right
  rugs:     [{ top: '75%', left: '50%' }],   // Area Rug — brown rug centered under table
  storage:  [
    { top: '55%', left: '22%' },             // Glass shelf, left of sofa
    { top: '50%', left: '8%' },              // Bookshelf — VASAGLE, far left wall
  ],
  decor:    [{ top: '20%', left: '48%' }],   // Wall Art — sun/moon prints above sofa
};

// Fallback for any extra products beyond the known categories
const PRODUCT_POSITIONS_FALLBACK = [
  { top: '65%', left: '48%' },
  { top: '52%', left: '82%' },
  { top: '63%', left: '60%' },
  { top: '75%', left: '50%' },
  { top: '50%', left: '8%' },
  { top: '55%', left: '22%' },
  { top: '20%', left: '48%' },
];

// Stable sort order so duplicate-category products get consistent fallback positions
const CATEGORY_ORDER = ['tables', 'seating', 'lighting', 'rugs', 'storage', 'decor'];
function sortProductsByCategory(products) {
  return [...products].sort((a, b) => {
    const ai = CATEGORY_ORDER.indexOf(a.category);
    const bi = CATEGORY_ORDER.indexOf(b.category);
    return (ai === -1 ? 99 : ai) - (bi === -1 ? 99 : bi);
  });
}

// Resolve position for a product, tracking per-category counts for multi-slot categories
function getProductPosition(product, categoryCounts, fallbackIndex) {
  const cat = product.category;
  const positions = CATEGORY_POSITIONS[cat];
  if (positions) {
    const idx = categoryCounts[cat] || 0;
    categoryCounts[cat] = idx + 1;
    if (idx < positions.length) return positions[idx];
  }
  return PRODUCT_POSITIONS_FALLBACK[fallbackIndex] || { top: '50%', left: '50%' };
}
