import { themes, brands, categories, categoryIcons } from '../data/mockData';

export default function DesignDrawer({
  theme,
  setTheme,
  budget,
  setBudget,
  roomImageUrl,
  setRoomImageUrl,
  selectedBrands,
  toggleBrand,
  priorities,
  togglePriority,
  mustHitBudget,
  setMustHitBudget,
  demoMode,
  toggleDemoMode,
  onClose,
}) {
  return (
    <>
      {/* Backdrop */}
      <div className="drawer-backdrop" onClick={onClose} />

      {/* Drawer */}
      <div className="drawer">
        <div className="drawer-header">
          <h2 className="drawer-title">Design Preferences</h2>
          <button className="drawer-close" onClick={onClose}>✕</button>
        </div>

        <div className="drawer-body">
          {/* ── Theme ── */}
          <section className="dp-section">
            <label className="dp-label">Room Theme</label>
            <div className="dp-theme-grid">
              {themes.map((t) => (
                <button
                  key={t.id}
                  className={`dp-theme-btn ${theme === t.id ? 'active' : ''}`}
                  onClick={() => setTheme(t.id)}
                >
                  {t.label}
                </button>
              ))}
            </div>
          </section>

          {/* ── Budget ── */}
          <section className="dp-section">
            <label className="dp-label">Total Budget</label>
            <div className="dp-budget-row">
              <span className="dp-budget-dollar">$</span>
              <input
                type="number"
                className="dp-budget-input"
                value={budget}
                onChange={(e) => setBudget(Number(e.target.value) || 0)}
                min={500}
                max={50000}
                step={100}
              />
            </div>
            <input
              type="range"
              className="dp-budget-slider"
              min={500}
              max={10000}
              step={100}
              value={budget}
              onChange={(e) => setBudget(Number(e.target.value))}
            />
            <div className="dp-budget-range">
              <span>$500</span>
              <span>$10,000</span>
            </div>
          </section>

          {/* ── Room Photo URL ── */}
          <section className="dp-section">
            <label className="dp-label">Room Photo URL</label>
            <input
              type="url"
              className="dp-budget-input"
              style={{ width: '100%', fontSize: '0.8rem' }}
              value={roomImageUrl}
              onChange={(e) => setRoomImageUrl(e.target.value)}
              placeholder="https://..."
            />
            <p className="dp-hint">
              Paste an image URL of your room for AI analysis.
            </p>
          </section>

          {/* ── Price Preference ── */}
          <section className="dp-section">
            <label className="dp-label">Pricing Preference</label>
            <div className="dp-toggle-row">
              <label className="dp-toggle">
                <input
                  type="checkbox"
                  checked={mustHitBudget}
                  onChange={(e) => setMustHitBudget(e.target.checked)}
                />
                <span className="dp-toggle-track">
                  <span className="dp-toggle-thumb" />
                </span>
                <span className="dp-toggle-text">Hit my budget</span>
              </label>
            </div>
            <p className="dp-hint">
              When enabled, we'll fill your room as close to $
              {budget.toLocaleString()} as possible with the best picks.
            </p>
          </section>

          {/* ── Demo Mode ── */}
          <section className="dp-section">
            <label className="dp-label">Demo Mode</label>
            <div className="dp-toggle-row">
              <label className="dp-toggle">
                <input
                  type="checkbox"
                  checked={!!demoMode}
                  onChange={() => toggleDemoMode && toggleDemoMode()}
                />
                <span className="dp-toggle-track">
                  <span className="dp-toggle-thumb" />
                </span>
                <span className="dp-toggle-text">Use fixed demo query</span>
              </label>
            </div>
            <p className="dp-hint">
              When enabled, the search always uses:
              <br />
              <code>mid-century modern furniture for Brooklyn loft living room with wood tones</code>
            </p>
          </section>

          {/* ── Brand Filter ── */}
          <section className="dp-section">
            <label className="dp-label">Preferred Brands</label>
            <div className="dp-chips">
              {brands.map((b) => (
                <button
                  key={b}
                  className={`dp-chip ${selectedBrands.includes(b) ? 'active' : ''}`}
                  onClick={() => toggleBrand(b)}
                >
                  {b}
                </button>
              ))}
            </div>
          </section>

          {/* ── Priority Focus ── */}
          <section className="dp-section">
            <label className="dp-label">
              Priority Focus <span className="dp-label-hint">(pick up to 3)</span>
            </label>
            <p className="dp-hint">
              If we go over budget, these categories stay — everything else gets
              trimmed first.
            </p>
            <div className="dp-priority-list">
              {categories.map((cat) => {
                const idx = priorities.indexOf(cat.id);
                const isSelected = idx !== -1;
                return (
                  <button
                    key={cat.id}
                    className={`dp-priority-btn ${isSelected ? 'active' : ''}`}
                    onClick={() => togglePriority(cat.id)}
                  >
                    <span className="dp-priority-icon">
                      {categoryIcons[cat.id]}
                    </span>
                    <span className="dp-priority-name">{cat.label}</span>
                    {isSelected && (
                      <span className="dp-priority-badge">{idx + 1}</span>
                    )}
                  </button>
                );
              })}
            </div>
          </section>
        </div>

        <div className="drawer-footer">
          <button className="btn-primary full" onClick={onClose}>
            Apply Preferences
          </button>
        </div>
      </div>
    </>
  );
}
