/* Eixo Colors - Generated from _data/eixo_colors.yml */
/* This script provides global JavaScript variables for eixo colors */

// Global eixo colors array (in order)
window.eixoColors = [
{% for color in site.data.eixo_colors.colors -%}
  "{{ color.hex }}"{% unless forloop.last %},{% endunless %} // {{ color.css_var }}
{% endfor %}
];

// Global eixo color mapping object for easy access
window.eixoColorMap = {
{% for color in site.data.eixo_colors.colors -%}
{% assign index = forloop.index0 %}
  "{{ color.name }}": {
    hex: "{{ color.hex }}",
    cssVar: "{{ color.css_var }}",
    badgeClass: "badge-eixo-{{ forloop.index }}",
    index: {{ index }}
  }{% unless forloop.last %},{% endunless %}
{% endfor %}
};

// Overflow color configuration
window.eixoOverflowColor = {
  hex: "{{ site.data.eixo_colors.overflow.hex }}",
  cssVar: "{{ site.data.eixo_colors.overflow.css_var }}",
  badgeClass: "badge-eixo-overflow"
};

// Helper function to get color by index (0-based)
window.getEixoColorByIndex = function(index) {
  if (index < window.eixoColors.length) {
    return window.eixoColors[index];
  }
  return window.eixoOverflowColor.hex;
};

// Helper function to get badge class by index (0-based)
window.getEixoBadgeClassByIndex = function(index) {
  if (index < window.eixoColors.length) {
    return `badge-eixo-${index + 1}`;
  }
  return window.eixoOverflowColor.badgeClass;
};
