import { categoryColors, categoryIcons } from '../data/mockData';

export default function ProductCard({
  product,
  isSelected,
  onToggle,
  priorityRank,
}) {
  const color = categoryColors[product.category];
  const icon = categoryIcons[product.category];

  return (
    <div className={`product-card ${isSelected ? 'selected' : ''}`}>
      {/* Image */}
      <div className="pc-image" style={{ '--accent': color }}>
        {product.image ? (
          <img src={product.image} alt={product.name} className="pc-image-photo" />
        ) : (
          <span className="pc-image-icon">{icon}</span>
        )}
        {priorityRank != null && (
          <span className="pc-priority-badge">#{priorityRank + 1} Priority</span>
        )}
      </div>

      {/* Details */}
      <div className="pc-body">
        <div className="pc-header">
          <span className="pc-brand">{product.brand}</span>
          <span className="pc-cat-tag" style={{ color }}>
            {product.category}
          </span>
        </div>
        <h4 className="pc-name">{product.name}</h4>
        <p className="pc-reason">{product.reason}</p>

        <div className="pc-footer">
          <div className="pc-price-row">
            <span className="pc-price">
              ${product.price.toLocaleString('en-US', { minimumFractionDigits: 2 })}
            </span>
            <span className="pc-rating">
              {'★'.repeat(Math.round(product.rating))}
              {'☆'.repeat(5 - Math.round(product.rating))}
              <span className="pc-rating-num">{Number(product.rating).toFixed(2)}</span>
              <span className="pc-reviews">({product.reviews.toLocaleString()})</span>
            </span>
          </div>
          <button
            className={`pc-toggle ${isSelected ? 'remove' : 'add'}`}
            onClick={() => onToggle(product.id)}
          >
            {isSelected ? '✕ Remove' : '+ Add to Room'}
          </button>
        </div>
      </div>
    </div>
  );
}
