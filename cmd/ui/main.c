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

	InitWindow(screen_width, screen_height, "raylib demo");

	struct jnl_pslg pslg = {0};
	jnl_pslg_init(&pslg);

	jnl_pslg_node_add(&pslg, 10, 10, 0);
	jnl_pslg_node_add(&pslg, 10, 300, 0);
	jnl_pslg_node_add(&pslg, 200, 200, 0);
	jnl_pslg_node_add(&pslg, 200, 10, 0);

	jnl_pslg_edge_add(&pslg, 0, 1, 0);
	jnl_pslg_edge_add(&pslg, 1, 2, 0);
	jnl_pslg_edge_add(&pslg, 2, 3, 0);
	jnl_pslg_edge_add(&pslg, 3, 0, 0);

	struct jnl_view2D view = {
	    .width = 600,
	    .height = 400,
	};

	Texture2D tex = pslg_gen_texture(&pslg, view);
	Vector2 texloc = {0, 0};

	SetTargetFPS(60);

	while (!WindowShouldClose()) {
		BeginDrawing();
		ClearBackground(RAYWHITE);
		DrawTextureV(tex, texloc, WHITE);
		DrawText("Test display of a PSLG", 190, 200, 20, LIGHTGRAY);
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

	f64 scale = width / bbw;
	if (scale * bbh > height) {
		scale = height / bbh;
	}

	// printf("bbox = [%f, %f], outer = [%d, %d], scale = %f\n", bbw, bbh,
	//        view.width, view.height, scale);

#define TX(x) (padding + scale * ((x) - bbox.min_x))
#define TY(y) (padding + height - (scale * (y - bbox.min_y)))

	// Use bbox, aspect ratio, centre and zoom level
	// to determine
	// transformation from PSLG coords to display coords

	struct jnl_node_array nodes = pslg->nodes;
	struct jnl_edge_array edges = pslg->edges;

	for (u32 i = 0; i < edges.len; i++) {
		jnl_vec2d p1 = nodes.coords[edges.ps[i]];
		jnl_vec2d p2 = nodes.coords[edges.qs[i]];
		Vector2 v1 = {TX(p1.x), TY(p1.y)}, v2 = {TX(p2.x), TY(p2.y)};
		ImageDrawLineEx(&img, v1, v2, 1, BLUE);
	}

	for (u32 i = 0; i < nodes.len; i++) {
		jnl_vec2d point = nodes.coords[i];
		Vector2 vec = {TX(point.x), TY(point.y)};
		ImageDrawCircleV(&img, vec, 3, BLACK);
	}

	Texture2D tex = LoadTextureFromImage(img);
	UnloadImage(img);

#undef TX
#undef TY

	return tex;
}
