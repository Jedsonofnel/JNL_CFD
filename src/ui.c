#include <raylib.h>
#include <stdio.h>
#include <unistd.h>

#include "ui.h"

FILE *jnl_ui_spawn(void)
{
	FILE *output;
	int pipes[2];
	pid_t pid;

	pipe(pipes);
	pid = fork();

	if (!pid) {
		dup2(pipes[0], STDIN_FILENO);
		jnl_ui_start();
		return NULL;
	}

	output = fdopen(pipes[1], "w");

	// pipe output to the file!

	return output;
}

void jnl_ui_start(void)
{
	const int screenWidth = 900;
	const int screenHeight = 600;

	InitWindow(screenWidth, screenHeight, "raylib intro");

	SetTargetFPS(60);

	while (!WindowShouldClose()) {
		BeginDrawing();
		ClearBackground(RAYWHITE);
		DrawText("Congrats, you created your first window!", 190,
			 200, 20, DARKGRAY);
		EndDrawing();
	}

	CloseWindow();

	return;
}
