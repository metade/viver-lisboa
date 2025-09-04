# Eixo Color Coding Feature

This document describes the implementation of color-coded badges for the `eixo` property in the Viver Lisboa Jekyll site.

## Overview

The `eixo` property from KML data is now automatically color-coded based on alphabetical order. Each unique `eixo` value is assigned one of 5 predefined colors, creating a consistent visual system across the entire map interface including markers, polygons, and badges.

## Color Scheme

The following colors are used in alphabetical order:

1. **#ed4154** (Red) - First eixo alphabetically
2. **#ffb91b** (Yellow) - Second eixo alphabetically  
3. **#66BC3D** (Green) - Third eixo alphabetically
4. **#7A3DBC** (Purple) - Fourth eixo alphabetically
5. **#4B5D73** (Dark Blue/Gray) - Fifth eixo alphabetically

## Implementation Details

### CSS Classes

The following CSS classes were added to `assets/css/theme.css` (using existing brand color variables):

- `.badge-eixo-1` - Red (var(--brand-red): #ed4154)
- `.badge-eixo-2` - Yellow (var(--brand-yellow): #ffb91b)
- `.badge-eixo-3` - Green (var(--brand-green): #66bc3d)
- `.badge-eixo-4` - Purple (var(--brand-purple): #7a3dbc)
- `.badge-eixo-5` - Slate (var(--brand-slate): #4b5d73)
- `.badge-eixo-overflow` - Black (#000000) for 6+ eixo values

**Benefits of using theme.css:**
- Colors are available across both map pages and regular content pages
- Leverages existing brand color variables for consistency
- Single source of truth for color definitions
- Easy to maintain and update globally

### JavaScript Functions

The following functions were added to `assets/js/map.js`:

#### `createEixoColorMapping(features)`
- Scans all features to find unique `eixo` values
- Sorts them alphabetically
- Assigns colors in the predefined order
- Handles cases with more than 5 unique values using overflow badges

#### `getEixoBadgeClass(eixo)`
- Returns the appropriate CSS class for a given eixo value
- Falls back to `badge-primary` if no mapping exists

#### `addEixoLegendToInfoPanel()`
- Dynamically adds a legend to the general information panel
- Shows all eixo values with their corresponding colors
- Maintains alphabetical order in the display

#### `createEixoColorExpression()`
- Generates MapLibre GL JS color expressions for map layers
- Creates conditional styling based on eixo property values
- Provides fallback colors for features without eixo data

#### `updateLayerColorsWithEixo()`
- Updates map marker and polygon colors to match eixo values
- Applies color-coding to both fill and stroke properties
- Adjusts opacity for optimal visibility

## Features

### Automatic Color Assignment
- Colors are assigned automatically when the map loads
- Assignment is based on alphabetical sorting of unique eixo values
- No manual configuration required

### Map Layer Color-Coding
- Markers (points) are colored based on their eixo values
- Polygons (fills and outlines) use the same color scheme
- Hover effects added for better interactivity
- Optimized opacity levels for visual clarity

### Selection Styling
- Selected markers show a thick black outline instead of color fill
- Selected polygons display a dashed black outline
- Black outline prevents confusion with red eixo color scheme
- Selection styling is visually distinct from eixo colors

### Visual Legend
- A legend is automatically added to the "Informações Gerais" panel
- Shows all eixo categories with their assigned colors
- Updates dynamically based on available data

### Fallback Handling
- If more than 5 unique eixo values exist, they use a black badge (`badge-eixo-overflow`) to clearly indicate the overflow
- This makes it obvious when there are more eixo categories than expected
- Graceful degradation if eixo data is missing
- Map layers fall back to default blue color for features without eixo data

## Usage

The feature works automatically when:
1. PMTiles data is loaded
2. Features contain an `eixo` property
3. The map initialization completes

Users will see:
- Color-coded badges in proposal detail panels
- Color-coded markers and polygons on the map
- A legend in the general information panel
- Consistent colors across all map interactions
- Hover effects when cursor is over interactive elements
- Black outline styling when markers or polygons are selected

### Console Logging

For debugging purposes, the following information is logged to the console:
- Number of features found
- Unique eixo values discovered
- Color assignments for each eixo
- Complete mapping object
- Map layer color updates confirmation
- Any overflow eixo values (6+) that receive the black badge

## Browser Compatibility

The implementation uses modern JavaScript features including:
- Set objects for unique value collection
- Array.from() for set conversion
- forEach() for iteration
- Template literals for HTML generation

This is compatible with all modern browsers that support MapLibre GL JS.