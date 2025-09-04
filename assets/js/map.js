// Map initialization and configuration
document.addEventListener("DOMContentLoaded", function () {
  // Initialize panel content from page templates
  initializePanelContent();
  // Add PMTiles protocol
  let protocol = new pmtiles.Protocol();
  maplibregl.addProtocol("pmtiles", protocol.tile);

  // Initialize the map
  const map = new maplibregl.Map({
    container: "map",
    style: {
      version: 8,
      sources: {
        "carto-light": {
          type: "raster",
          tiles: [
            "https://cartodb-basemaps-a.global.ssl.fastly.net/light_all/{z}/{x}/{y}.png",
            "https://cartodb-basemaps-b.global.ssl.fastly.net/light_all/{z}/{x}/{y}.png",
            "https://cartodb-basemaps-c.global.ssl.fastly.net/light_all/{z}/{x}/{y}.png",
            "https://cartodb-basemaps-d.global.ssl.fastly.net/light_all/{z}/{x}/{y}.png",
          ],
          tileSize: 256,
          attribution:
            '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors &copy; <a href="https://carto.com/attributions">CARTO</a>',
        },
      },
      layers: [
        {
          id: "carto-light-layer",
          type: "raster",
          source: "carto-light",
          minzoom: 0,
          maxzoom: 22,
        },
      ],
    },
    center: [-9.13628, 38.72614], // Arroios center coordinates
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
  map.on("click", function (e) {
    console.log("Map clicked at:", e.lngLat);
  });

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
        "fill-opacity": 0.4,
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
        "circle-opacity": 0.8,
      },
    });

    // Auto-focus map on Freguesia border when data loads
    map.on("sourcedata", function (e) {
      if (e.sourceId === "pmtiles-source" && e.isSourceLoaded) {
        const freguesiaFeatures = map.querySourceFeatures("pmtiles-source", {
          sourceLayer: "border",
        });

        if (freguesiaFeatures.length > 0) {
          // Get freguesia bounds and fit map to them
          const bounds = new maplibregl.LngLatBounds();
          freguesiaFeatures[0].geometry.coordinates[0].forEach((coord) => {
            bounds.extend(coord);
          });

          // Fit map to freguesia bounds with padding
          map.fitBounds(bounds, {
            padding: 50,
            maxZoom: 15,
            duration: 1500,
          });
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
        "circle-color": "#dc3545",
        "circle-stroke-color": "#ffffff",
        "circle-stroke-width": 3,
        "circle-opacity": 0.9,
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
      type: "fill",
      source: "propostas-polygons-selected",
      paint: {
        "fill-color": "#dc3545",
        "fill-opacity": 0.6,
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
      panelContent += `<p><span class="badge badge-primary">${properties["eixo"]}</span></p>`;
    }

    return addCommonPanelElements(panelContent, properties);
  }

  // Helper function to add common panel elements (link and images)
  function addCommonPanelElements(panelContent, properties) {
    // Add link to full proposal page if slug exists
    if (properties["slug"] && properties["slug"].trim() !== "") {
      panelContent += `
        <div class="mt-3 mb-3">
          <a href="./propostas/${properties["slug"]}" class="btn btn-primary btn-sm">
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
    // Add single map click handler that prioritizes markers over polygons
    map.on("click", function (e) {
      // Query all features at the click point
      const markerFeatures = map.queryRenderedFeatures(e.point, {
        layers: ["propostas-markers"],
      });

      const polygonFeatures = map.queryRenderedFeatures(e.point, {
        layers: ["propostas-polygons-fill"],
      });

      // Prioritize markers over polygons
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
      } else if (polygonFeatures.length > 0) {
        // Handle polygon click (only if no markers are present)
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
