//
// Pure rendering functions for domain visualisation
//

const foreground = "#192234";
const background = "#f8f9fc";

// Visual constants
const REGION_COLORS = [
	"#e3f2fd", // light blue
	"#fff3e0", // light orange
	"#f3e5f5", // light purple
	"#e8f5e9", // light green
	"#fce4ec", // light pink
	"#fff9c4", // light yellow
	"#f0f4c3", // light lime
	"#b2dfdb", // light teal
];

// Stroke widths
const POLYGON_STROKE_WIDTH = 1;
const BOUNDARY_STROKE_WIDTH = 2;
const HOLE_STROKE_WIDTH = 1;
const HOLE_DASH_PATTERN = [5, 5];

// Colors
const POLYGON_STROKE_COLOR = foreground;
const BOUNDARY_STROKE_COLOR = foreground;
const HOLE_STROKE_COLOR = foreground;
const HOLE_FILL_COLOR = background;
const LABEL_COLOR = foreground;

const LABEL_FONT_SIZE = 18;

function renderPolygon(ctx, poly, transform, options) {
	const points = poly.points;
	const numPoints = points.length / 2;

	ctx.beginPath();
	for (let i = 0; i < numPoints; i++) {
		const [x, y] = transform.domainToCanvas(points[i * 2], points[i * 2 + 1]);
		if (i === 0) {
			ctx.moveTo(x, y);
		} else {
			ctx.lineTo(x, y);
		}
	}
	ctx.closePath();

	// Style based on whether it's a hole
	if (poly["is-hole"]) {
		if (!options.transparent) {
			ctx.fillStyle = HOLE_FILL_COLOR;
			ctx.fill();
		}
		ctx.strokeStyle = HOLE_STROKE_COLOR;
		ctx.lineWidth = HOLE_STROKE_WIDTH;
		ctx.setLineDash(HOLE_DASH_PATTERN);
	} else {
		if (!options.transparent) {
			const regionId = poly["region-id"] || 0;
			const color = REGION_COLORS[regionId % REGION_COLORS.length];
			ctx.fillStyle = color;
			ctx.fill();
		}
		ctx.strokeStyle = POLYGON_STROKE_COLOR;
		ctx.lineWidth = POLYGON_STROKE_WIDTH;
		ctx.setLineDash([]);
	}

	ctx.stroke();
}

function renderBoundaries(ctx, poly, transform) {
	const points = poly.points;
	const boundaries = poly.boundaries;
	const numPoints = points.length / 2;

	ctx.strokeStyle = BOUNDARY_STROKE_COLOR;
	ctx.lineWidth = BOUNDARY_STROKE_WIDTH;
	ctx.setLineDash([]);

	for (let i = 0; i < numPoints; i++) {
		const boundary = boundaries[i];

		if (boundary && boundary !== "") {
			const [x1, y1] = transform.domainToCanvas(
				points[i * 2],
				points[i * 2 + 1],
			);
			const nextIdx = (i + 1) % numPoints;
			const [x2, y2] = transform.domainToCanvas(
				points[nextIdx * 2],
				points[nextIdx * 2 + 1],
			);

			ctx.beginPath();
			ctx.moveTo(x1, y1);
			ctx.lineTo(x2, y2);
			ctx.stroke();
		}
	}
}

function renderLabel(ctx, poly, transform) {
	const points = poly.points;
	const numPoints = points.length / 2;

	// Calculate centroid in domain coords
	let cx = 0,
		cy = 0;
	for (let i = 0; i < numPoints; i++) {
		cx += points[i * 2];
		cy += points[i * 2 + 1];
	}
	cx /= numPoints;
	cy /= numPoints;

	// Convert to canvas coords
	const [canvasX, canvasY] = transform.domainToCanvas(cx, cy);

	ctx.font = `bold ${LABEL_FONT_SIZE}px monospace`;
	ctx.fillStyle = LABEL_COLOR;
	ctx.textAlign = "center";
	ctx.textBaseline = "middle";
	ctx.fillText(poly.region || "region", canvasX, canvasY);
}

export function renderDomain(ctx, transform, data, options = {}) {
	const opts = {
		showBoundaries: options.showBoundaries ?? true,
		showLabels: options.showLabels ?? true,
		transparent: options.transparent ?? false, // New: stroke-only mode
	};

	// Clear canvas (unless transparent overlay mode)
	if (!opts.transparent) {
		ctx.clearRect(0, 0, ctx.canvas.width, ctx.canvas.height);
	}

	const polygonsSorted = [...data.polygons].sort((a, b) => {
		const layerA = a.layer ?? 0;
		const layerB = b.layer ?? 0;
		return layerA - layerB;
	});

	// Render all polygons
	polygonsSorted.forEach((poly) => {
		renderPolygon(ctx, poly, transform, opts);

		if (opts.showBoundaries) {
			renderBoundaries(ctx, poly, transform);
		}

		if (opts.showLabels && !poly["is-hole"]) {
			renderLabel(ctx, poly, transform);
		}
	});
}
