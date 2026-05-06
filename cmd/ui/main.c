#include <stdlib.h>
#include <raylib.h>

#include "jnl/common.h"
#include "geo2d.h"

Texture2D pslg_gen_texture(struct jnl_pslg *pslg);

int main(void)
{
	i32 screen_width = 800;
	i32 screen_height = 450;

	InitWindow(screen_width, screen_height, "raylib demo");

	struct jnl_pslg pslg = {0};
	jnl_pslg_init(&pslg);

	jnl_pslg_node_add(&pslg, 10, 10, 0);
	jnl_pslg_node_add(&pslg, 10, 200, 0);
	jnl_pslg_node_add(&pslg, 200, 200, 0);
	jnl_pslg_node_add(&pslg, 200, 10, 0);

	jnl_pslg_edge_add(&pslg, 0, 1, 0);
	jnl_pslg_edge_add(&pslg, 1, 2, 0);
	jnl_pslg_edge_add(&pslg, 2, 3, 0);
	jnl_pslg_edge_add(&pslg, 3, 0, 0);

	Texture2D tex = pslg_gen_texture(&pslg);
	Vector2 texloc = {10, 20};

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

Texture2D pslg_gen_texture(struct jnl_pslg *pslg)
{
	Image img = GenImageColor(600, 400, WHITE);
	struct jnl_node_array nodes = pslg->nodes;
	struct jnl_edge_array edges = pslg->edges;

	for (u32 i = 0; i < edges.len; i++) {
		jnl_vec2d p1 = nodes.coords[edges.ps[i]];
		jnl_vec2d p2 = nodes.coords[edges.qs[i]];
		Vector2 v1 = {p1.x, p1.y}, v2 = {p2.x, p2.y};
		ImageDrawLineEx(&img, v1, v2, 1, BLUE);
	}

	for (u32 i = 0; i < nodes.len; i++) {
		jnl_vec2d point = nodes.coords[i];
		Vector2 vec = {point.x, point.y};
		ImageDrawCircleV(&img, vec, 5, BLACK);
	}

	return LoadTextureFromImage(img);
}
