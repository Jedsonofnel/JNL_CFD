import { renderDomain } from "../lib/domain-renderer.js";
import { renderField } from "../lib/field-renderer.js";
import { EDNParser } from "../lib/edn-parser.js";
import { renderMesh } from "../lib/mesh-renderer.js";
import { ViewportTransform } from "../lib/viewport-transform.js";

export class Visualiser {
	constructor(element, context) {
		this.element = element;
		this.context = context;
		this.data = this.parseData();
		this.canvasWebGL = null;
		this.canvas2D = null;
		this.ctx2d = null;
		this.ctxWebGL = null;
		this.transform = null;
		this.canvasWrapper = null;
		this.resizeObserver = null;

		// Render options
		this.options = {
			padding: 0.02,
			showBoundaries: true,
			showLabels: true,
			transparent: true,
		};

		console.log("Visualiser initialized with data:", this.data);
		this.init();
	}

	parseData() {
		const payloadAttr = this.element.getAttribute("data-payload");
		if (payloadAttr) {
			try {
				return new EDNParser(payloadAttr).parse();
			} catch (e) {
				console.error("Failed to parse payload:", e);
				return null;
			}
		}
		return null;
	}

	calculateAspectRatio() {
		let bounds = this.data.bounds;
		if (!bounds && this.data.domain) {
			bounds = this.data.domain.bounds;
		}

		if(!bounds && this.data.mesh) {
			bounds = this.data.mesh.domain.bounds;
		}

		if (!bounds) {
			return 4 / 3; // Default aspect ratio
		}

		const domainWidth = bounds["max-x"] - bounds["min-x"];
		const domainHeight = bounds["max-y"] - bounds["min-y"];

		// Add padding to the aspect ratio calculation
		const padding = Math.max(domainWidth, domainHeight) * this.options.padding;
		const viewWidth = domainWidth + 2 * padding;
		const viewHeight = domainHeight + 2 * padding;

		return viewWidth / viewHeight;
	}

	init() {
		if (!this.data) {
			this.element.innerHTML = "<p>No visualization data available</p>";
			return;
		}

		// Create container structure
		const container = this.element;

		const title = document.createElement("h3");
		title.className = "viz-title";
		title.textContent = this.data.title || "Visualization";
		container.appendChild(title);

		// Create canvas wrapper for layering
		this.canvasWrapper = document.createElement("div");
		this.canvasWrapper.className = "viz-canvas-container";

		const aspectRatio = this.calculateAspectRatio();
		this.canvasWrapper.style.aspectRatio = aspectRatio.toString();

		const type = this.getDataType();

		if (type === "mesh" || type == "field-viz") {
			// Create WebGL canvas (bottom layer)
			this.canvasWebGL = document.createElement("canvas");
			this.canvasWebGL.className = "viz-canvas-webgl";
			this.canvasWrapper.appendChild(this.canvasWebGL);

			this.ctxWebGL =
				this.canvasWebGL.getContext("webgl2") ||
				this.canvasWebGL.getContext("webgl");
			if (!this.ctxWebGL) {
				console.error("WebGL not supported");
				return;
			}

			// Create 2D canvas for overlay (top layer)
			if (this.data.domain) {
				this.canvas2D = document.createElement("canvas");
				this.canvas2D.className = "viz-canvas-2d";
				this.canvasWrapper.appendChild(this.canvas2D);

				this.ctx2d = this.canvas2D.getContext("2d");
			}
		} else {
			// Just 2D canvas for domain-only
			this.canvas2D = document.createElement("canvas");
			this.canvas2D.className = "viz-canvas-2d";
			this.canvasWrapper.appendChild(this.canvas2D);

			this.ctx2d = this.canvas2D.getContext("2d");
		}

		container.appendChild(this.canvasWrapper);

		this.setupResizeObserver();
		this.updateCanvasSize();
	}

	setupResizeObserver() {
		this.resizeObserver = new ResizeObserver((entries) => {
			for (const _ of entries) {
				this.updateCanvasSize();
			}
		});

		this.resizeObserver.observe(this.canvasWrapper);
	}

	updateCanvasSize() {
		const rect = this.canvasWrapper.getBoundingClientRect();
		const width = Math.floor(rect.width);
		const height = Math.floor(rect.height);

		// Update WebGL canvas
		if (this.canvasWebGL) {
			this.canvasWebGL.width = width;
			this.canvasWebGL.height = height;
			if (this.ctxWebGL) {
				this.ctxWebGL.viewport(0, 0, width, height);
			}
		}

		// Update 2D canvas
		if (this.canvas2D) {
			this.canvas2D.width = width;
			this.canvas2D.height = height;
		}

		// Recalculate transform and re-render
		this.updateTransform();
		this.render();
	}

	getDataType() {
		return typeof this.data.type === "symbol"
			? this.data.type.description.slice(1)
			: this.data.type;
	}

	updateTransform() {
		let bounds = this.data.bounds;
		if (!bounds && this.data.domain) {
			bounds = this.data.domain.bounds;
		}

		if (!bounds && this.data.mesh) {
			bounds = this.data.mesh.domain.bounds;
		}

		if (!bounds) {
			console.warn("No bounds found in data");
			return;
		}

		const width = this.canvasWebGL?.width || this.canvas2D?.width || 800;
		const height = this.canvasWebGL?.height || this.canvas2D?.height || 600;

		this.transform = new ViewportTransform(
			bounds,
			width,
			height,
			this.options.padding,
		);
	}

	render() {
		if (!this.transform) {
			return;
		}

		const type = this.getDataType();

		switch (type) {
		case "domain":
			if (!this.ctx2d) {
				console.error("2D context not available");
				return;
			}
			renderDomain(this.ctx2d, this.transform, this.data, this.options);
			break;

		case "mesh":
			if (!this.ctxWebGL) {
				console.error("WebGL context not available");
				return;
			}

			renderMesh(this.ctxWebGL, this.transform, this.data, {
				lineColor: [0.2, 0.2, 0.2, 1.0],
				lineWidth: 1.0,
				clear: true,
			});

			if (this.data.domain && this.ctx2d) {
				renderDomain(this.ctx2d, this.transform, this.data.domain, {
					...this.options,
					transparent: true, // Stroke-only overlay
				});
			}
			break;

		case "field-viz":
			if (!this.ctxWebGL) {
				console.error("WebGL context not available");
				return;
			}

			renderField(this.ctxWebGL, this.transform, this.data, {
				colorMap: "hot",
				clear: true,
			})

		default:
			if (this.ctx2d) {
				this.ctx2d.font = "20px monospace";
				this.ctx2d.fillStyle = "#666";
				this.ctx2d.textAlign = "center";
				this.ctx2d.fillText(
					`Unknown visualization type: ${type}`,
					this.canvas2D.width / 2,
					this.canvas2D.height / 2,
				);
			}
		}
	}

	destroy() {
		// Disconnect resize observer
		if (this.resizeObserver) {
			this.resizeObserver.disconnect();
			this.resizeObserver = null;
		}

		if (this.canvasWebGL) {
			this.canvasWebGL.remove();
			this.canvasWebGL = null;
			this.ctxWebGL = null;
		}
		if (this.canvas2D) {
			this.canvas2D.remove();
			this.canvas2D = null;
			this.ctx2d = null;
		}
		this.transform = null;
		this.canvasWrapper = null;
	}
}
