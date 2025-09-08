# Viver Lisboa - AI Agent Guide

## Project Overview
Political campaign site for Lisbon municipal elections using Jekyll + MapLibre GL JS for interactive maps. This is a multi-freguesia (district) site where each freguesia has its own interactive map with political proposals.

## Architecture

### Deployment Strategy
- **Production**: Multi-subdomain deployment (e.g., `alvalade.viver-lisboa.org`, `arroios.viver-lisboa.org`)
- **Development**: Single domain with `/freguesias/{slug}/` path structure
- **URL Routing**: Custom Jekyll plugin handles production/development URL differences

### Technology Stack
- **Static Site**: Jekyll 4.4.1
- **Maps**: MapLibre GL JS 5.7.0 with PMTiles 4.3.0
- **UI Framework**: Bootstrap 5.3.8
- **Data Format**: GeoJSON for boundaries, PMTiles for map tiles
- **Asset Management**: Custom fingerprinting plugin

## Key Components

### 1. Map System (`assets/js/map.js`)
**615 lines** of complex MapLibre GL JS integration with:
- **Eixo Color System**: 5-color theme for proposal categories
  ```javascript
  const eixoColors = [
    "#ed4154", // --brand-red
    "#ffb91b", // --brand-yellow  
    "#66bc3d", // --brand-green
    "#7a3dbc", // --brand-purple
    "#4b5d73", // --brand-slate
  ];
  ```
- **Dynamic Content Loading**: Bootstrap offcanvas panels
- **Marker Management**: Proposal points with popup details
- **Layer Management**: Border highlighting and selection styling

### 2. Jekyll Plugins (`_plugins/`)
- **`freguesia_url_helper.rb`**: Critical URL routing logic
  - `freguesia_relative_url()`: Handles prod/dev URL differences
  - `freguesia_propostas_url()`: Generates proposal page URLs
  - Production uses subdomains, development uses paths
- **`asset_hash.rb`**: Asset fingerprinting for cache busting

### 3. Layout System
- **`_layouts/freguesia_map.html`**: Primary map layout
  - Loads MapLibre CSS/JS and PMTiles
  - Sets up map container and overlay UI
  - Includes Bootstrap offcanvas for details panel
- **`_layouts/default.html`**: Standard page layout

### 4. Content Structure
```
freguesias/
├── alvalade/
│   └── index.html          # Map page with proposals
├── arroios/
│   └── index.html
└── santo-antonio/
    └── index.html

data/freguesias/
├── alvalade/
│   └── border.geojson      # Geographic boundary
├── arroios/
│   └── border.geojson
└── santo-antonio/
    └── border.geojson
```

### 5. Asset Pipeline
- **CSS**: Theme colors, map styles, responsive design
- **JavaScript**: Map initialization, interaction handlers
- **Data**: GeoJSON → PMTiles conversion via Ruby scripts

## Data Flow

### Page Load Sequence
1. Jekyll renders `freguesia_map.html` layout
2. JavaScript loads PMTiles data from `assets/data/{slug}.pmtiles`
3. Map initializes with boundary GeoJSON
4. Proposal markers loaded from embedded page data
5. Click handlers setup for interactive elements

### Content Templates
Freguesia pages use embedded HTML templates:
- `#generalInfoContent`: General information panel
- `#markerContent`: Dynamic proposal details (populated by JS)
- `#defaultContent`: Default state when no marker selected

## Common Modification Patterns

### Adding New Freguesia
1. **Create page**: `/freguesias/{slug}/index.html`
   ```yaml
   ---
   layout: freguesia_map
   title: Viver {Name}
   freguesia: {Name}
   freguesia_slug: {slug}
   parties: [ps, livre, bloco, pan]
   ---
   ```

2. **Add boundary data**: `/data/freguesias/{slug}/border.geojson`

3. **Generate tiles**: Run `scripts/prepare_pmtiles.rb`

### Map Styling Changes
- **Colors**: Modify `eixoColors` array in `map.js` (lines 7-13)
- **Markers**: Update marker styling in `loadPropostasLayer()` function
- **UI Elements**: Bootstrap classes with custom CSS overrides in `map.css`

### Content Updates
- **Proposals**: Embed in freguesia HTML files as hidden div templates
- **Panel Content**: Use `data-content-type` and `data-panel-title` attributes
- **Dynamic Loading**: JavaScript reads templates and populates offcanvas

### URL Changes
- **Development**: Modify baseurl in `_config.yml`
- **Production**: Update domain logic in `freguesia_url_helper.rb`
- **Cross-linking**: Use provided helper functions, never hardcode URLs

## Important Constraints & Gotchas

### Technical Limitations
- **Max 5 Eixo Categories**: Limited by color array, overflow uses black
- **PMTiles Regeneration**: Required after any GeoJSON boundary changes
- **Cross-Domain URLs**: Production requires absolute URLs due to subdomain setup

### Development vs Production
- **URL Generation**: Always use helper functions, never hardcode
- **Asset References**: Use `asset_url` filter for fingerprinted assets
- **Local Testing**: May not perfectly mirror production subdomain behavior

### Performance Considerations
- **Asset Fingerprinting**: Enabled for cache busting
- **Map Tiles**: PMTiles format optimized for web delivery
- **JavaScript**: Single 615-line file, consider splitting for large additions

## Scripts & Utilities

### Ruby Scripts (`scripts/`)
- **`download_maps.rb`**: Fetches map data
- **`prepare_pmtiles.rb`**: Converts GeoJSON to PMTiles
- **`asset_utils.rb`**: Asset processing utilities

### Build Process
```bash
# Development
bundle exec jekyll serve

# Production build  
JEKYLL_ENV=production bundle exec jekyll build
```

## Party System
Multi-party coalition site supporting:
- **PS** (Socialist Party)
- **LIVRE** (Free Party) 
- **Bloco** (Left Bloc)
- **PAN** (People-Animals-Nature)

Party logos and styling managed via `{% include parties.html %}`.

## Integration Points
- **External Forms**: Proposal submission via external apps
- **Analytics**: Google Analytics integration in production
- **SEO**: Jekyll SEO tag plugin for meta tags
- **Social**: Open Graph and Twitter Card support

---

*This documentation is designed to help AI agents understand the unique architecture and make informed modifications to the Viver Lisboa campaign site.*