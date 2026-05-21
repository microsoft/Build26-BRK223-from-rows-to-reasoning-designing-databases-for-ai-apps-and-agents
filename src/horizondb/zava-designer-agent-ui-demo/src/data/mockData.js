/* ── Themes ── */
export const themes = [
  { id: 'mid-century', label: 'Mid-Century Modern' },
  { id: 'scandinavian', label: 'Scandinavian' },
  { id: 'industrial', label: 'Industrial' },
  { id: 'bohemian', label: 'Bohemian' },
  { id: 'minimalist', label: 'Minimalist' },
  { id: 'contemporary', label: 'Contemporary' },
];

/* ── Brands (from actual DB stores) ── */
export const brands = [
  'VASAGLE',
  'Yaheetech',
  'Art Leon',
  'SAFAVIEH',
  'Furinno',
  'HUGOAI',
  'Unique Loom',
  'nuLOOM',
  'ArtbyHannah',
  'Rolanstar',
];

/* ── Furniture categories for priority picking ── */
export const categories = [
  { id: 'seating', label: 'Seating' },
  { id: 'tables', label: 'Tables' },
  { id: 'lighting', label: 'Lighting' },
  { id: 'rugs', label: 'Rugs & Textiles' },
  { id: 'storage', label: 'Storage' },
  { id: 'decor', label: 'Decor & Art' },
];

/* ── Category colors for product card accents ── */
export const categoryColors = {
  seating: '#C45C3A',
  tables: '#92702A',
  lighting: '#B8860B',
  rugs: '#7C5B8D',
  storage: '#4A7C6E',
  decor: '#5B7FA1',
};

/* ── Category icons (emoji stand-ins) ── */
export const categoryIcons = {
  seating: '🛋️',
  tables: '☕',
  lighting: '💡',
  rugs: '🧶',
  storage: '📚',
  decor: '🖼️',
};

/* ── Mock AI-suggested products (from product_metadata DB) ── */
export const suggestedProducts = [
  {
    id: 2289594,
    name: 'VASAGLE Coffee Table with Mesh Shelf',
    brand: 'VASAGLE',
    price: 85.99,
    category: 'tables',
    rating: 4.6,
    reviews: 6749,
    image: 'https://m.media-amazon.com/images/I/71AgU73rZ7L._AC_SL1500_.jpg',
    reason:
      'Industrial rustic style with steel frame matches the loft\'s exposed brick perfectly.',
  },
  {
    id: 231413,
    name: 'Art Leon Mid Century Swivel Accent Chair',
    brand: 'Art Leon',
    price: 149.99,
    category: 'seating',
    rating: 4.5,
    reviews: 4511,
    image: 'https://m.media-amazon.com/images/I/91C5gW7dn5S._AC_SL1500_.jpg',
    reason:
      'Suede mid-century silhouette pairs beautifully with the chevron sofa.',
  },
  {
    id: 293527,
    name: 'HUGOAI LED Table Lamp with RGB Color Changing',
    brand: 'HUGOAI',
    price: 36.99,
    category: 'lighting',
    rating: 4.5,
    reviews: 10895,
    image: 'https://m.media-amazon.com/images/I/61fadJZneBL._AC_SL1500_.jpg',
    reason:
      'Tunable warm-to-cool light sets the mood, compact enough for the side table.',
  },
  {
    id: 1764388,
    name: 'SAFAVIEH Madison Boho Chic Area Rug, 10\'x14\'',
    brand: 'SAFAVIEH',
    price: 235.94,
    category: 'rugs',
    rating: 4.6,
    reviews: 26856,
    image: 'https://m.media-amazon.com/images/I/A1conrokczL._AC_SL1500_.jpg',
    reason:
      'Navy and teal tones complement the brick walls while grounding the seating area.',
  },
  {
    id: 45108,
    name: 'Furinno 3-Tier Adjustable Bookshelf',
    brand: 'Furinno',
    price: 39.99,
    category: 'storage',
    rating: 4.0,
    reviews: 32136,
    image: 'https://m.media-amazon.com/images/I/71jEcQW3jML._AC_SL1500_.jpg',
    reason:
      'Affordable open shelving adds vertical interest without overwhelming the space.',
  },
  {
    id: 251451,
    name: 'Furinno Andrey End Table Set of 2',
    brand: 'Furinno',
    price: 42.48,
    category: 'tables',
    rating: 4.1,
    reviews: 54113,
    image: 'https://m.media-amazon.com/images/I/51nYZlVsKvL._AC_SL1012_.jpg',
    reason:
      'Compact nightstand-style tables slot beside the sofa and chair for drinks and remotes.',
  },
  {
    id: 1413734,
    name: 'ArtbyHannah Botanical Framed Wall Art Set',
    brand: 'ArtbyHannah',
    price: 32.99,
    category: 'decor',
    rating: 4.6,
    reviews: 2617,
    image: 'https://m.media-amazon.com/images/I/81D+mPtlAIL._AC_SL1500_.jpg',
    reason:
      'Green botanical prints bring life to the brick wall above the sofa.',
  },
];

/* ── Default state for the demo ── */
export const defaultDesignBrief = {
  theme: 'mid-century',
  budget: 2000,
  selectedBrands: ['VASAGLE', 'Art Leon', 'SAFAVIEH', 'Furinno'],
  priorities: ['seating', 'tables', 'lighting'],
  mustHitBudget: true,
};
