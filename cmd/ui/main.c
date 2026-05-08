#include <stdlib.h>
#include <raylib.h>

#include "jnl/common.h"
#include "geo2d.h"

struct jnl_view2D {
	Vector2 centre; // [0,0] as default centre
	f32 zoom;       // 1 = fit contained
	i32 width;
	i32 height;
};

Texture2D pslg_gen_texture(struct jnl_pslg *, struct jnl_view2D);

int main(void)
{
	i32 screen_width = 800;
	i32 screen_height = 450;

	InitWindow(screen_width, screen_height, "JNLCFD Visualiser");

	struct jnl_pslg pslg = {0};
	jnl_pslg_init(&pslg);

	jnl_pslg_node_add(&pslg, 10, 10, 0);
	jnl_pslg_node_add(&pslg, 10, 300, 0);
	jnl_pslg_node_add(&pslg, 200, 200, 0);
	jnl_pslg_node_add(&pslg, 200, 10, 0);
	jnl_pslg_node_add(&pslg, 100, 96, 0);
	jnl_pslg_node_add(&pslg, 500, 96, 0);

	jnl_pslg_edge_add(&pslg, 0, 1, 0);
	jnl_pslg_edge_add(&pslg, 1, 2, 0);
	jnl_pslg_edge_add(&pslg, 2, 3, 0);
	jnl_pslg_edge_add(&pslg, 3, 0, 0);
	jnl_pslg_edge_add(&pslg, 3, 4, 0);
	jnl_pslg_edge_add(&pslg, 3, 5, 0);

	struct jnl_view2D view = {
	    .centre = {0.0, 0.0},
	    .zoom = 1.0,
	    .width = screen_width,
	    .height = screen_height - 50,
	};

	Texture2D tex = pslg_gen_texture(&pslg, view);
	Vector2 texloc = {0, 0};

	SetTargetFPS(60);

	char buf[100];
	sprintf(buf, "PSLG display: %d nodes, %d edges", pslg.nodes.len,
	        pslg.edges.len);

	while (!WindowShouldClose()) {
		BeginDrawing();
		ClearBackground(WHITE);
		DrawTextureV(tex, texloc, WHITE);

		DrawText(buf, 10, screen_height - 35, 20, BLACK);
		EndDrawing();
	}

	CloseWindow();

	UnloadTexture(tex);

	jnl_pslg_free(&pslg);

	return EXIT_SUCCESS;
}

Texture2D pslg_gen_texture(struct jnl_pslg *pslg, struct jnl_view2D view)
{
	Image img = GenImageColor(view.width, view.height, WHITE);

	f64 padding = 10;
	f64 width = (f64)view.width - 2 * padding;
	f64 height = (f64)view.height - 2 * padding;

	struct jnl_aabb bbox = jnl_pslg_bbox(pslg);
	f64 bbw = bbox.max_x - bbox.min_x, bbh = bbox.max_y - bbox.min_y;

	f64 scale = view.zoom * width / bbw;
	if (scale * bbh > height) {
		scale = height / bbh;
	}

	f64 dx = ((1 + view.centre.x) * width - (bbw * scale)) / 2;
	f64 dy = ((bbh * scale) - (1 + view.centre.y) * height) / 2;

#define TX(x) (padding + dx + scale * ((x) - bbox.min_x))
#define TY(y) (padding + dy + height - (scale * (y - bbox.min_y)))

	struct jnl_node_array nodes = pslg->nodes;
	struct jnl_edge_array edges = pslg->edges;

	for (u32 i = 0; i < edges.len; i++) {
		jnl_vec2d p1 = nodes.coords[edges.ps[i]];
		jnl_vec2d p2 = nodes.coords[edges.qs[i]];
		Vector2 v1 = {TX(p1.x), TY(p1.y)}, v2 = {TX(p2.x), TY(p2.y)};
		ImageDrawLineEx(&img, v1, v2, 2, BLUE);
	}

	for (u32 i = 0; i < nodes.len; i++) {
		jnl_vec2d point = nodes.coords[i];
		Vector2 vec = {TX(point.x), TY(point.y)};
		ImageDrawCircleV(&img, vec, 4, BLACK);
	}

#undef TX
#undef TY

	Texture2D tex = LoadTextureFromImage(img);
	UnloadImage(img);

	return tex;
}
