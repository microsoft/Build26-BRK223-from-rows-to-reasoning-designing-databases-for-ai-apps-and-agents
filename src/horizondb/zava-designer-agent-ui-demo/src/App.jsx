import { useState, useCallback, useRef } from 'react';
import AgentTrace from './components/AgentTrace';
import DesignDrawer from './components/DesignDrawer';
import QueryTrace from './components/QueryTrace';
import RoomView from './components/RoomView';
import SuggestionsPanel from './components/SuggestionsPanel';
import {
  suggestedProducts as mockProducts,
  defaultDesignBrief,
} from './data/mockData';

export default function App() {
  /* ── Design brief state ── */
  const [theme, setTheme] = useState(defaultDesignBrief.theme);
  const [budget, setBudget] = useState(defaultDesignBrief.budget);
  const [roomImageUrl, setRoomImageUrl] = useState('');
  const [selectedBrands, setSelectedBrands] = useState(
    defaultDesignBrief.selectedBrands,
  );
  const [priorities, setPriorities] = useState(defaultDesignBrief.priorities);
  const [mustHitBudget, setMustHitBudget] = useState(
    defaultDesignBrief.mustHitBudget,
  );

  /* ── Product & trace state ── */
  const [products, setProducts] = useState(mockProducts);
  const [agentTraceData, setAgentTraceData] = useState(null);
  const [selectedIds, setSelectedIds] = useState(
    new Set(mockProducts.map((p) => p.id)),
  );
  const [isDesigned, setIsDesigned] = useState(false);
  const [isDesigning, setIsDesigning] = useState(false);
  const [designStep, setDesignStep] = useState(0);
  const [showSuggestions, setShowSuggestions] = useState(false);
  const [showDrawer, setShowDrawer] = useState(false);
  const [showTrace, setShowTrace] = useState(false);
  const [showAgentTrace, setShowAgentTrace] = useState(false);
  const [cartAdded, setCartAdded] = useState(false);
  const [highlightedProductId, setHighlightedProductId] = useState(null);
  const [demoMode, setDemoMode] = useState(() => {
    try {
      const v = localStorage.getItem('zava-demo-mode');
      return v === null ? true : v === '1';
    } catch { return true; }
  });
  const stepTimerRef = useRef(null);

  const handleProductDotClick = useCallback((productId) => {
    setShowSuggestions(true);
    setHighlightedProductId(productId);
  }, []);

  const toggleDemoMode = useCallback(() => {
    setDemoMode((prev) => {
      const next = !prev;
      try { localStorage.setItem('zava-demo-mode', next ? '1' : '0'); } catch {}
      return next;
    });
  }, []);

  const handleAddToCart = useCallback(() => {
    setCartAdded(true);
    setTimeout(() => setCartAdded(false), 2000);
  }, []);

  /* ── Handlers ── */
  const toggleProduct = (id) => {
    setSelectedIds((prev) => {
      const next = new Set(prev);
      next.has(id) ? next.delete(id) : next.add(id);
      return next;
    });
  };

  const TOTAL_STEPS = 6;

  const handleDesignMyRoom = useCallback(async () => {
    if (isDesigning || isDesigned) return;
    setIsDesigning(true);
    setDesignStep(0);

    // Start step animation while API call runs
    let step = 0;
    stepTimerRef.current = setInterval(() => {
      step += 1;
      if (step < TOTAL_STEPS) {
        setDesignStep(step);
      }
    }, 800);

    try {
      const res = await fetch('/api/design-room', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          theme,
          budget,
          priorities,
          brands: selectedBrands,
          demoMode,
          ...(roomImageUrl && { roomImageUrl }),
        }),
      });

      if (!res.ok) throw new Error(`API error: ${res.status}`);
      const data = await res.json();

      // Stop step animation and jump to done
      clearInterval(stepTimerRef.current);
      setDesignStep(TOTAL_STEPS);

      if (data.products && data.products.length > 0) {
        setProducts(data.products);
        setSelectedIds(new Set(data.products.map((p) => p.id)));
      } else {
        // Fallback to mock data
        setProducts(mockProducts);
        setSelectedIds(new Set(mockProducts.map((p) => p.id)));
      }

      if (data.trace) {
        setAgentTraceData(data.trace);
      }

      setTimeout(() => {
        setIsDesigning(false);
        setIsDesigned(true);
      }, 400);
    } catch (err) {
      console.error('Design API failed, using mock data:', err);
      clearInterval(stepTimerRef.current);
      setDesignStep(TOTAL_STEPS);
      setProducts(mockProducts);
      setSelectedIds(new Set(mockProducts.map((p) => p.id)));
      setAgentTraceData(null);
      setTimeout(() => {
        setIsDesigning(false);
        setIsDesigned(true);
      }, 400);
    }
  }, [isDesigning, isDesigned, theme, budget, priorities, selectedBrands, demoMode]);

  const handleRedesign = useCallback(() => {
    setIsDesigned(false);
    setIsDesigning(false);
    setDesignStep(0);
    setShowSuggestions(false);
    setShowTrace(false);
    setShowAgentTrace(false);
    setCartAdded(false);
    setAgentTraceData(null);
    if (stepTimerRef.current) clearInterval(stepTimerRef.current);
  }, []);

  const toggleBrand = (brand) => {
    setSelectedBrands((prev) =>
      prev.includes(brand)
        ? prev.filter((b) => b !== brand)
        : [...prev, brand],
    );
  };

  const togglePriority = (catId) => {
    setPriorities((prev) => {
      if (prev.includes(catId)) return prev.filter((c) => c !== catId);
      if (prev.length >= 3) return prev;
      return [...prev, catId];
    });
  };

  /* ── Derived values ── */
  const selectedProducts = products.filter((p) =>
    selectedIds.has(p.id),
  );
  const totalSpent = selectedProducts.reduce((s, p) => s + p.price, 0);

  return (
    <>
      {/* ── Header ── */}
      <header className="header">
        <div className="header-left">
          <div className="logo">
            <img src="/zava-logo.png" alt="Zava" className="logo-img" />
          </div>
          <nav className="nav">
            <a className="nav-link active" href="#">Room Designer</a>
            <a className="nav-link" href="#">Catalog</a>
            <a className="nav-link" href="#">My Rooms</a>
          </nav>
        </div>
        <div className="header-right">
          {isDesigned && (
            <button
              className={`toggle-suggestions-btn ${showSuggestions ? 'active' : ''}`}
              onClick={() => setShowSuggestions(!showSuggestions)}
              title={showSuggestions ? 'Hide suggestions' : 'Show suggestions'}
            >
              {showSuggestions ? '◀ Hide Picks' : '▶ Show Picks'}
            </button>
          )}
          {isDesigned && (
            <button
              className={`toggle-trace-btn ${showTrace ? 'active' : ''}`}
              onClick={() => setShowTrace(!showTrace)}
              title="Show what happened under the hood"
            >
              {showTrace ? '✕ Close' : '⚡ How did this work?'}
            </button>
          )}
          <div className="active-users">
            <span className="pulse" />
            <span>2,847 designing now</span>
          </div>
          <div className="avatar">A</div>
        </div>
      </header>

      {/* ── Main layout ── */}
      <div className={`app-layout ${showSuggestions ? '' : 'full-room'}`}>
        <main className="panel-center">
          <RoomView
            selectedProducts={selectedProducts}
            isDesigned={isDesigned}
            isDesigning={isDesigning}
            designStep={designStep}
            onDesignMyRoom={handleDesignMyRoom}
            onRedesign={handleRedesign}
            onProductDotClick={handleProductDotClick}
          />
          {isDesigned && (
            <button
              className="agent-details-btn"
              onClick={() => setShowAgentTrace(true)}
              title="View agent tool calls"
            >
              ⚙️ Agent Details
            </button>
          )}
          <button
            className="settings-fab"
            onClick={() => setShowDrawer(true)}
            title="Design preferences"
          >
            🎨
          </button>
        </main>

        {showDrawer && (
          <DesignDrawer
            theme={theme}
            setTheme={setTheme}
            budget={budget}
            setBudget={setBudget}
            roomImageUrl={roomImageUrl}
            setRoomImageUrl={setRoomImageUrl}
            selectedBrands={selectedBrands}
            toggleBrand={toggleBrand}
            priorities={priorities}
            togglePriority={togglePriority}
            mustHitBudget={mustHitBudget}
            setMustHitBudget={setMustHitBudget}
            demoMode={demoMode}
            toggleDemoMode={toggleDemoMode}
            onClose={() => setShowDrawer(false)}
          />
        )}

        {showSuggestions && (
          <aside className="panel-right panel-right-enter">
            <SuggestionsPanel
              products={products}
              selectedIds={selectedIds}
              toggleProduct={toggleProduct}
              priorities={priorities}
              budget={budget}
              totalSpent={totalSpent}
              isDesigned={isDesigned}
              highlightedProductId={highlightedProductId}
              onHighlightConsumed={() => setHighlightedProductId(null)}
            />
          </aside>
        )}
      </div>

      {/* ── Query trace overlay ── */}
      <QueryTrace isVisible={showTrace} onClose={() => setShowTrace(false)} />

      {/* ── Agent trace overlay ── */}
      <AgentTrace isVisible={showAgentTrace} onClose={() => setShowAgentTrace(false)} traceData={agentTraceData} />

      {/* ── Bottom budget bar (only after design) ── */}
      {isDesigned && (
        <footer className="budget-footer budget-footer-enter">
          <div className="budget-footer-inner">
            <div className="budget-summary">
              <span className="budget-label">Total</span>
              <span className="budget-amount">${totalSpent.toLocaleString('en-US', { minimumFractionDigits: 2 })}</span>
              <span className="budget-divider">/</span>
              <span className="budget-cap">${budget.toLocaleString()}</span>
            </div>
            <div className="budget-bar-wrap">
              <div
                className="budget-bar-fill"
                style={{
                  width: `${Math.min((totalSpent / budget) * 100, 100)}%`,
                  backgroundColor:
                    totalSpent > budget
                      ? 'var(--danger)'
                      : totalSpent / budget > 0.85
                        ? 'var(--warning)'
                        : 'var(--success)',
                }}
              />
            </div>
            <span className="budget-remaining">
              {totalSpent <= budget
                ? `$${(budget - totalSpent).toLocaleString('en-US', { minimumFractionDigits: 2 })} remaining`
                : `$${(totalSpent - budget).toLocaleString('en-US', { minimumFractionDigits: 2 })} over budget`}
            </span>
          </div>
          <div className="budget-actions">
            <button className="btn-outline">Share Design</button>
            <button
              className={`btn-primary btn-add-to-cart${cartAdded ? ' added' : ''}`}
              onClick={handleAddToCart}
              disabled={cartAdded}
            >
              {cartAdded ? (
                <><span className="cart-check">✓</span> Added to Cart</>
              ) : (
                <><span className="cart-icon">🛒</span> Add to Cart</>
              )}
            </button>
          </div>
        </footer>
      )}
    </>
  );
}
