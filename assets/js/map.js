// Map initialization and configuration
// Map center coordinates are now dynamically loaded from each freguesia's front matter
// instead of being hardcoded for Arroios. Each freguesia page defines its own map_center
// coordinates as an array [lng, lat] in the front matter, which are passed through pageData.
//
// The automatic bounds fitting combines ALL border features from the PMTiles source since
// complex freguesia geometries can be split across multiple vector tiles. This ensures
// proper zoom level regardless of how the geometry is tiled in the PMTiles data.
document.addEventListener("DOMContentLoaded", function () {
  // Global variable to store eixo color mapping
  let eixoColorMapping = {};

  // Flag to prevent multiple initialization
  let isDataInitialized = false;

  // Colors for eixo property (in order) - matching theme.css brand colors
  const eixoColors = [
    "#ed4154", // --brand-red
    "#ffb91b", // --brand-yellow
    "#66bc3d", // --brand-green
    "#7a3dbc", // --brand-purple
    "#4b5d73", // --brand-slate
    // extra colours
    "#2d9cdb", // --brand-blue (bright sky blue for contrast)
    "#1a2b3c", // --brand-navy (deep grounding neutral)
    "#f4f2ef", // --brand-ivory (soft off-white background)
    "#e67a9c", // --brand-pink (playful highlight)
    "#2bbbad", // --brand-teal (fresh secondary accent)
  ];

  // Function to create eixo color mapping based on alphabetical order
  function createEixoColorMapping(features) {
    const uniqueEixos = new Set();

    // Collect all unique eixo values from features
    features.forEach((feature) => {
      if (feature.properties && feature.properties.eixo) {
        uniqueEixos.add(feature.properties.eixo);
      }
    });

    // Sort alphabetically and assign colors
    const sortedEixos = Array.from(uniqueEixos).sort();
    sortedEixos.forEach((eixo, index) => {
      if (index < eixoColors.length) {
        eixoColorMapping[eixo] = {
          color: eixoColors[index],
          classIndex: index + 1,
        };
      } else {
        // Fallback for more than 5 eixo values - use overflow badge
        console.warn(
          `⚠️ Eixo overflow: "${eixo}" (position ${index + 1}) using black badge. Consider adding more colors.`,
        );
        eixoColorMapping[eixo] = {
          color: "#000000",
          classIndex: "overflow",
        };
      }
    });

    console.log("Eixo color mapping created:", eixoColorMapping);
    console.log("Found eixo values:", sortedEixos);
    console.log("Color assignments:");
    sortedEixos.forEach((eixo, index) => {
      if (index < eixoColors.length) {
        console.log(
          `  ${eixo}: ${eixoColors[index]} (badge-eixo-${index + 1})`,
        );
      }
    });
  }

  // Function to get eixo badge class
  function getEixoBadgeClass(eixo) {
    if (eixoColorMapping[eixo]) {
      return `badge-eixo-${eixoColorMapping[eixo].classIndex}`;
    }
    return "badge-primary"; // fallback
  }

  // Function to create MapLibre color expression based on eixo values
  function createEixoColorExpression() {
    const expression = ["case"];

    // Add each eixo value and its color to the expression
    Object.keys(eixoColorMapping).forEach((eixo) => {
      expression.push(["==", ["get", "eixo"], eixo]);
      expression.push(eixoColorMapping[eixo].color);
    });

    // Default fallback color
    expression.push("#3b82f6");

    return expression;
  }

  // Function to update map layer colors based on eixo mapping
  function updateLayerColorsWithEixo() {
    if (Object.keys(eixoColorMapping).length === 0) {
      return; // No eixo mapping yet
    }

    const colorExpression = createEixoColorExpression();

    // Update polygon fill color (with lower opacity for better marker visibility)
    map.setPaintProperty(
      "propostas-polygons-fill",
      "fill-color",
      colorExpression,
    );
    map.setPaintProperty("propostas-polygons-fill", "fill-opacity", 0.25);

    // Update polygon outline color
    map.setPaintProperty(
      "propostas-polygons-outline",
      "line-color",
      colorExpression,
    );
    map.setPaintProperty("propostas-polygons-outline", "line-opacity", 0.8);

    // Update linestring color
    map.setPaintProperty(
      "propostas-linestrings",
      "line-color",
      colorExpression,
    );
    map.setPaintProperty("propostas-linestrings", "line-opacity", 0.8);

    // Update marker color
    map.setPaintProperty("propostas-markers", "circle-color", colorExpression);
    map.setPaintProperty("propostas-markers", "circle-opacity", 0.9);

    console.log("Updated map layer colors with eixo-based styling");
  }
  // Initialize panel content from page templates
  initializePanelContent();
  // Add PMTiles protocol
  let protocol = new pmtiles.Protocol();
  maplibregl.addProtocol("pmtiles", protocol.tile);

  // Initialize the map
  const MAPTILER_KEY = "BlScxjvw8WYk3TGxzgU8";

  const map = new maplibregl.Map({
    container: "map",
    style: `https://api.maptiler.com/maps/positron/style.json?key=${MAPTILER_KEY}`,
    center:
      window.pageData && window.pageData.mapCenter
        ? window.pageData.mapCenter
        : [-9.13628, 38.72614], // Arroios fallback
    zoom: 14,
  });

  // Add navigation control (the +/- zoom buttons)
  map.addControl(new maplibregl.NavigationControl(), "top-right");

  // Add geolocate control
  map.addControl(
    new maplibregl.GeolocateControl({
      positionOptions: {
        enableHighAccuracy: true,
      },
      trackUserLocation: true,
      showUserHeading: true,
    }),
    "top-right",
  );

  // Add scale control
  map.addControl(
    new maplibregl.ScaleControl({
      maxWidth: 100,
      unit: "metric",
    }),
    "bottom-left",
  );

  // Optional: Add a marker at the center
  // Uncomment the lines below to add a marker
  // new maplibregl.Marker()
  //   .setLngLat([-9.142, 38.736])
  //   .addTo(map);

  // Log when map is loaded
  map.on("load", function () {
    console.log("Map loaded successfully!");

    // Load PMTiles data and add propostas layer
    loadPropostasLayer();
  });

  // Optional: Add click event listener
  // map.on("click", function (e) {
  //   console.log("Map clicked at:", e.lngLat);
  // });

  // Function to load propostas layer from PMTiles
  function loadPropostasLayer() {
    // Add PMTiles source
    map.addSource("pmtiles-source", {
      type: "vector",
      url: "pmtiles://" + window.pageData.pmtilesUrl,
    });

    // Add Freguesia border outline
    map.addLayer({
      id: "freguesia-border-outline",
      type: "line",
      source: "pmtiles-source",
      "source-layer": "border",
      paint: {
        "line-color": "#3dadbc",
        "line-width": 3,
        "line-opacity": 0.8,
      },
    });

    // Add propostas layer for polygon geometries (fill) - render first so markers appear on top
    map.addLayer({
      id: "propostas-polygons-fill",
      type: "fill",
      source: "pmtiles-source",
      "source-layer": "propostas",
      filter: ["==", ["geometry-type"], "Polygon"],
      paint: {
        "fill-color": "#3b82f6",
        "fill-opacity": 0.3,
      },
    });

    // Add propostas layer for polygon geometries (outline)
    map.addLayer({
      id: "propostas-polygons-outline",
      type: "line",
      source: "pmtiles-source",
      "source-layer": "propostas",
      filter: ["==", ["geometry-type"], "Polygon"],
      paint: {
        "line-color": "#3b82f6",
        "line-width": 2,
        "line-opacity": 0.9,
      },
    });

    // Add propostas layer for LineString geometries
    map.addLayer({
      id: "propostas-linestrings",
      type: "line",
      source: "pmtiles-source",
      "source-layer": "propostas",
      filter: ["==", ["geometry-type"], "LineString"],
      paint: {
        "line-color": "#3b82f6",
        "line-width": 4,
        "line-opacity": 0.8,
      },
    });

    // Add propostas layer for point geometries (circles/markers) - render last so they appear on top
    map.addLayer({
      id: "propostas-markers",
      type: "circle",
      source: "pmtiles-source",
      "source-layer": "propostas",
      filter: ["==", ["geometry-type"], "Point"],
      paint: {
        "circle-radius": 8,
        "circle-color": "#3b82f6",
        "circle-stroke-color": "#ffffff",
        "circle-stroke-width": 2,
        "circle-opacity": 0.9,
      },
    });

    // Add hover effects for markers
    map.on("mouseenter", "propostas-markers", () => {
      map.getCanvas().style.cursor = "pointer";
    });

    map.on("mouseleave", "propostas-markers", () => {
      map.getCanvas().style.cursor = "";
    });

    // Add hover effects for polygons
    map.on("mouseenter", "propostas-polygons-fill", () => {
      map.getCanvas().style.cursor = "pointer";
    });

    map.on("mouseleave", "propostas-polygons-fill", () => {
      map.getCanvas().style.cursor = "";
    });

    // Add hover effects for linestrings
    map.on("mouseenter", "propostas-linestrings", () => {
      map.getCanvas().style.cursor = "pointer";
    });

    map.on("mouseleave", "propostas-linestrings", () => {
      map.getCanvas().style.cursor = "";
    });

    // Auto-focus map on Freguesia border when data loads
    map.on("sourcedata", function (e) {
      if (
        e.sourceId === "pmtiles-source" &&
        e.isSourceLoaded &&
        !isDataInitialized
      ) {
        isDataInitialized = true;

        // Create eixo color mapping from propostas features
        const propostasFeatures = map.querySourceFeatures("pmtiles-source", {
          sourceLayer: "propostas",
        });
        console.log("Found", propostasFeatures.length, "propostas features");
        createEixoColorMapping(propostasFeatures);

        // Update map layer colors with eixo-based styling
        updateLayerColorsWithEixo();

        // Add eixo legend to info panel
        addEixoLegendToInfoPanel();

        const freguesiaFeatures = map.querySourceFeatures("pmtiles-source", {
          sourceLayer: "border",
        });

        console.log(
          `Found ${freguesiaFeatures.length} border features for ${window.pageData?.freguesiaSlug}`,
        );

        if (freguesiaFeatures.length > 0) {
          // Combine all border features into one bounds calculation
          // Get freguesia bounds from ALL border features
          const bounds = new maplibregl.LngLatBounds();

          freguesiaFeatures.forEach((feature) => {
            const geometry = feature.geometry;

            if (geometry.type === "Polygon") {
              // For Polygon, coordinates[0] is the outer ring
              geometry.coordinates[0].forEach((coord) => {
                bounds.extend(coord);
              });
            } else if (geometry.type === "MultiPolygon") {
              // For MultiPolygon, iterate through all polygons
              geometry.coordinates.forEach((polygon) => {
                // For each polygon, use the outer ring (polygon[0])
                polygon[0].forEach((coord) => {
                  bounds.extend(coord);
                });
              });
            }
          });

          // Get the center of the calculated bounds
          const boundsCenter = bounds.getCenter();
          const intendedCenter =
            window.pageData && window.pageData.mapCenter
              ? window.pageData.mapCenter
              : [-9.13628, 38.72614];

          // Always try to fit bounds, but adjust parameters based on freguesia
          const freguesiaSlug = window.pageData?.freguesiaSlug || "unknown";

          console.log(`Freguesia: ${freguesiaSlug}`);
          console.log(
            `Intended center: [${intendedCenter[0]}, ${intendedCenter[1]}]`,
          );
          console.log(
            `Bounds center: [${boundsCenter.lng}, ${boundsCenter.lat}]`,
          );
          console.log(`Bounds:`, bounds.toArray());

          // Adjust fit bounds parameters based on freguesia
          let fitOptions = {
            padding: 50,
            duration: 1500,
          };

          // Different freguesias may need different zoom constraints
          switch (freguesiaSlug) {
            case "arroios":
              fitOptions.maxZoom = 15;
              break;
            case "alvalade":
              fitOptions.maxZoom = 14;
              fitOptions.padding = 100;
              break;
            case "santo-antonio":
              fitOptions.maxZoom = 14;
              fitOptions.padding = 100;
              break;
            default:
              fitOptions.maxZoom = 14;
              break;
          }

          console.log(`Applying fitBounds with options:`, fitOptions);
          map.fitBounds(bounds, fitOptions);
        }
      }
    });

    // Add hover effect for markers
    map.on("mouseenter", "propostas-markers", function () {
      map.getCanvas().style.cursor = "pointer";
    });

    map.on("mouseleave", "propostas-markers", function () {
      map.getCanvas().style.cursor = "";
    });

    // Add hover effect for polygons
    map.on("mouseenter", "propostas-polygons-fill", function () {
      map.getCanvas().style.cursor = "pointer";
    });

    map.on("mouseleave", "propostas-polygons-fill", function () {
      map.getCanvas().style.cursor = "";
    });

    // Add hover effect for linestrings
    map.on("mouseenter", "propostas-linestrings", function () {
      map.getCanvas().style.cursor = "pointer";
    });

    map.on("mouseleave", "propostas-linestrings", function () {
      map.getCanvas().style.cursor = "";
    });

    console.log("Propostas layer loaded successfully!");

    // Set up click handlers after a small delay to ensure layers are fully registered
    setTimeout(() => {
      setupClickHandlers();
    }, 100);
  }

  // Helper function to remove previous selection styling
  function removeSelectionStyling() {
    if (map.getLayer("propostas-markers-selected")) {
      map.removeLayer("propostas-markers-selected");
      map.removeSource("propostas-markers-selected");
    }
    if (map.getLayer("propostas-polygons-selected")) {
      map.removeLayer("propostas-polygons-selected");
      map.removeSource("propostas-polygons-selected");
    }
    if (map.getLayer("propostas-linestrings-selected")) {
      map.removeLayer("propostas-linestrings-selected");
      map.removeSource("propostas-linestrings-selected");
    }
  }

  // Helper function to add highlight styling for markers
  function highlightMarker(feature) {
    map.addSource("propostas-markers-selected", {
      type: "geojson",
      data: {
        type: "FeatureCollection",
        features: [feature],
      },
    });

    map.addLayer({
      id: "propostas-markers-selected",
      type: "circle",
      source: "propostas-markers-selected",
      paint: {
        "circle-radius": 12,
        "circle-color": "transparent",
        "circle-stroke-color": "#000000",
        "circle-stroke-width": 5,
        "circle-stroke-opacity": 0.8,
      },
    });
  }

  // Helper function to add highlight styling for polygons
  function highlightPolygon(feature) {
    map.addSource("propostas-polygons-selected", {
      type: "geojson",
      data: {
        type: "FeatureCollection",
        features: [feature],
      },
    });

    map.addLayer({
      id: "propostas-polygons-selected",
      type: "line",
      source: "propostas-polygons-selected",
      paint: {
        "line-color": "#000000",
        "line-width": 5,
        "line-opacity": 0.8,
        "line-dasharray": [2, 2],
      },
    });
  }

  // Helper function to add highlight styling for linestrings
  function highlightLineString(feature) {
    map.addSource("propostas-linestrings-selected", {
      type: "geojson",
      data: {
        type: "FeatureCollection",
        features: [feature],
      },
    });

    map.addLayer({
      id: "propostas-linestrings-selected",
      type: "line",
      source: "propostas-linestrings-selected",
      paint: {
        "line-color": "#000000",
        "line-width": 6,
        "line-opacity": 0.9,
        "line-dasharray": [3, 3],
      },
    });
  }

  // Helper function to create panel content for both markers and polygons
  function createPanelContent(properties) {
    // Use the appropriate title property (Name for markers, name for polygons)
    const title = properties["Name"] || properties["name"] || "Proposta";

    let panelContent = `<h3>${title}</h3>`;

    // Add main proposta content
    if (properties["proposta"]) {
      panelContent += `<p class="lead">${properties["proposta"]}</p>`;
    }

    // Add description (for markers) or sumario (for polygons)
    if (properties["description"]) {
      panelContent += `<p>${properties["description"]}</p>`;
    } else if (properties["sumario"]) {
      panelContent += `<p>${properties["sumario"]}</p>`;
    }

    // Add eixo badge if it exists (for polygons)
    if (properties["eixo"]) {
      const badgeClass = getEixoBadgeClass(properties["eixo"]);
      panelContent += `<p><span class="badge ${badgeClass}">${properties["eixo"]}</span></p>`;
    }

    return addCommonPanelElements(panelContent, properties);
  }

  // Function to add eixo legend to the general info panel
  function addEixoLegendToInfoPanel() {
    const infoPanel = document.getElementById("generalInfoContent");
    if (!infoPanel || Object.keys(eixoColorMapping).length === 0) {
      return;
    }

    // Create legend HTML
    let legendHTML = `
      <div class="mb-3 pb-2 border-bottom">
        <div class="fw-semibold text-body-secondary small text-uppercase mb-2">
          Eixos
        </div>
        <div class="text-dark">
    `;

    // Sort eixos alphabetically for display
    const sortedEixos = Object.keys(eixoColorMapping).sort();

    sortedEixos.forEach((eixo) => {
      const badgeClass = getEixoBadgeClass(eixo);
      legendHTML += `
        <div class="d-flex align-items-center mb-1">
          <span class="badge ${badgeClass} me-2" style="min-width: 20px; font-size: 0.7rem;">&nbsp;</span>
          <span class="small">${eixo}</span>
        </div>
      `;
    });

    legendHTML += `
        </div>
      </div>
    `;

    // Insert the legend before the last div (navigation section)
    const lastSection = infoPanel.querySelector(".mb-0");
    if (lastSection) {
      lastSection.insertAdjacentHTML("beforebegin", legendHTML);
    }
  }

  // Helper function to add common panel elements (link and images)
  function addCommonPanelElements(panelContent, properties) {
    // Add link to full proposal page if slug exists
    if (properties["slug"] && properties["slug"].trim() !== "") {
      panelContent += `
        <div class="mt-3 mb-3">
          <a href="./propostas/${properties["slug"]}/" class="btn btn-primary btn-sm">
            <i class="bi bi-arrow-right-circle-fill me-2"></i>
            Ver Proposta Completa
          </a>
        </div>
      `;
    }

    // Add images if gx_media_links exists
    if (
      properties["gx_media_links"] &&
      properties["gx_media_links"].trim() !== ""
    ) {
      const imageUrls = properties["gx_media_links"].trim().split(/\s+/);
      panelContent += '<div class="mt-3">';
      imageUrls.forEach((imageUrl, index) => {
        panelContent += `
          <img src="${imageUrl}" class="img-fluid rounded mb-2" alt="Proposta image ${index + 1}" style="max-width: 100%; height: auto; display: block;">
        `;
      });
      panelContent += "</div>";
    }

    return panelContent;
  }

  // Helper function to show panel with content
  function showPanelWithContent(panelContent) {
    // Show marker content and populate it
    showPanelContent("markerContent");
    const markerContentInPanel = document.querySelector(
      "#panelBody #markerContent",
    );
    if (markerContentInPanel) {
      markerContentInPanel.innerHTML = panelContent;
    }

    // Show the offcanvas panel
    const panel = new bootstrap.Offcanvas(
      document.getElementById("detailsPanel"),
    );
    panel.show();
  }

  // Function to set up click handlers (called after layers are loaded)
  function setupClickHandlers() {
    // Add single map click handler that prioritizes markers over polygons and linestrings
    map.on("click", function (e) {
      // Query all features at the click point
      const markerFeatures = map.queryRenderedFeatures(e.point, {
        layers: ["propostas-markers"],
      });

      const polygonFeatures = map.queryRenderedFeatures(e.point, {
        layers: ["propostas-polygons-fill"],
      });

      const linestringFeatures = map.queryRenderedFeatures(e.point, {
        layers: ["propostas-linestrings"],
      });

      // Prioritize markers over polygons and linestrings
      if (markerFeatures.length > 0) {
        // Handle marker click
        const properties = markerFeatures[0].properties;

        // Remove previous selection styling
        removeSelectionStyling();

        // Highlight selected marker
        highlightMarker(markerFeatures[0]);

        // Create panel content and show panel
        const panelContent = createPanelContent(properties);
        showPanelWithContent(panelContent);
      } else if (linestringFeatures.length > 0) {
        // Handle linestring click (priority over polygons)
        const properties = linestringFeatures[0].properties;

        // Remove previous selection styling
        removeSelectionStyling();

        // Highlight selected linestring
        highlightLineString(linestringFeatures[0]);

        // Create panel content and show panel
        const panelContent = createPanelContent(properties);
        showPanelWithContent(panelContent);
      } else if (polygonFeatures.length > 0) {
        // Handle polygon click (lowest priority)
        const properties = polygonFeatures[0].properties;

        // Remove previous selection styling
        removeSelectionStyling();

        // Highlight selected polygon
        highlightPolygon(polygonFeatures[0]);

        // Create panel content and show panel
        const panelContent = createPanelContent(properties);
        showPanelWithContent(panelContent);
      }
    });
  }

  // Initialize panel content from page templates
  function initializePanelContent() {
    const panelBody = document.getElementById("panelBody");
    const contentTemplates = document.querySelectorAll(".panel-content");

    // Move all panel content templates to the panel body
    contentTemplates.forEach((template) => {
      const clonedTemplate = template.cloneNode(true);
      panelBody.appendChild(clonedTemplate);
    });

    // Show default content initially
    showPanelContent("defaultContent");
  }

  // Utility function to switch panel content
  function showPanelContent(contentId) {
    // Hide all panel content sections in the panel body
    document
      .querySelectorAll("#panelBody .panel-content")
      .forEach((content) => {
        content.classList.add("d-none");
      });

    // Show the requested content
    const targetContent = document.querySelector(`#panelBody #${contentId}`);
    if (targetContent) {
      targetContent.classList.remove("d-none");

      // Update panel title from data attribute
      const title = targetContent.getAttribute("data-panel-title");
      if (title) {
        document.getElementById("detailsPanelLabel").textContent = title;
      }
    }
  }

  // Add event listener for the more info button
  document.getElementById("moreInfoBtn").addEventListener("click", function () {
    // Remove previous selection styling if exists
    removeSelectionStyling();

    // Show general info content
    showPanelContent("generalInfoContent");

    // Show the offcanvas panel
    const panel = new bootstrap.Offcanvas(
      document.getElementById("detailsPanel"),
    );
    panel.show();
  });

  // Expose map to global scope for debugging
  window.mapInstance = map;
});
