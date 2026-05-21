import { themes, brands, categories, categoryIcons } from '../data/mockData';

export default function DesignPanel({
  theme,
  setTheme,
  budget,
  setBudget,
  selectedBrands,
  toggleBrand,
  priorities,
  togglePriority,
  mustHitBudget,
  setMustHitBudget,
  onDesign,
  isDesigned,
  onRedesign,
}) {
  return (
    <div className="design-panel">
      <h2 className="panel-title">Design Brief</h2>

      {/* ── Room Photo ── */}
      <section className="dp-section">
        <label className="dp-label">Room Photo</label>
        <div className="dp-upload">
          <div className="dp-upload-icon">📷</div>
          <span className="dp-upload-text">Brooklyn apartment · Living room</span>
          <span className="dp-upload-sub">Drop a photo or click to upload</span>
        </div>
      </section>

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
        <label className="dp-label">Priority Focus <span className="dp-label-hint">(pick up to 3)</span></label>
        <p className="dp-hint">
          If we go over budget, these categories stay — everything else gets trimmed first.
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
                <span className="dp-priority-icon">{categoryIcons[cat.id]}</span>
                <span className="dp-priority-name">{cat.label}</span>
                {isSelected && (
                  <span className="dp-priority-badge">{idx + 1}</span>
                )}
              </button>
            );
          })}
        </div>
      </section>

      {/* ── Action ── */}
      <div className="dp-action">
        {isDesigned ? (
          <button className="btn-outline full" onClick={onRedesign}>
            ← Edit Brief
          </button>
        ) : (
          <button className="btn-primary full" onClick={onDesign}>
            ✨ Design My Room
          </button>
        )}
      </div>
    </div>
  );
}
