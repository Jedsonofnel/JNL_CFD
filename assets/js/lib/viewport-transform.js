//
// Shared coordinate transformation utilities for canvas and WebGL
//

export class ViewportTransform {
	constructor(bounds, canvasWidth, canvasHeight, paddingRatio = 0.1) {
		const domainWidth = bounds["max-x"] - bounds["min-x"];
		const domainHeight = bounds["max-y"] - bounds["min-y"];

		// Add padding
		const padding = Math.max(domainWidth, domainHeight) * paddingRatio;
		const viewMinX = bounds["min-x"] - padding;
		const viewMinY = bounds["min-y"] - padding;
		const viewWidth = domainWidth + 2 * padding;
		const viewHeight = domainHeight + 2 * padding;

		// Calculate scale to fit canvas
		const scaleX = canvasWidth / viewWidth;
		const scaleY = canvasHeight / viewHeight;
		const scale = Math.min(scaleX, scaleY);

		this.scale = scale;
		this.offsetX = -viewMinX * scale;
		this.offsetY = -viewMinY * scale;
		this.canvasWidth = canvasWidth;
		this.canvasHeight = canvasHeight;
		this.viewWidth = viewWidth;
		this.viewHeight = viewHeight;
		this.viewMinX = viewMinX;
		this.viewMinY = viewMinY;
	}

	// Convert domain coordinates to canvas coordinates (Y-flipped)
	domainToCanvas(x, y) {
		const tx = x * this.scale + this.offsetX;
		const ty = this.canvasHeight - (y * this.scale + this.offsetY);
		return [tx, ty];
	}

	// Convert domain coordinates to normalized device coordinates [-1, 1]
	// Useful for WebGL
	domainToNDC(x, y) {
		const [cx, cy] = this.domainToCanvas(x, y);
		return [(cx / this.canvasWidth) * 2 - 1, 1 - (cy / this.canvasHeight) * 2];
	}

	// Scale a length from domain space to canvas space
	scaleLength(length) {
		return length * this.scale;
	}

	// Get WebGL projection matrix (orthographic)
	getProjectionMatrix() {
		// Returns parameters for orthographic projection
		return {
			left: this.viewMinX,
			right: this.viewMinX + this.viewWidth,
			bottom: this.viewMinY,
			top: this.viewMinY + this.viewHeight,
		};
	}
}
