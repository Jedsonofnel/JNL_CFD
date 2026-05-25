#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <string.h>
#include <readline/readline.h>
#include <readline/history.h>

#include "lua_bindings.h"

#ifndef LUA_ASSET_PATH
#define LUA_ASSET_PATH "../lua" // fallback default
#endif

//
// Helpers
//

static void set_lua_path(lua_State *L)
{
	lua_getglobal(L, "package");
	lua_pushstring(L, LUA_ASSET_PATH "/?.lua;" LUA_ASSET_PATH "/?/init.lua");
	lua_setfield(L, -2, "path");
	lua_pop(L, 1);
}

static void usage(const char *prog)
{
	fprintf(
	    stderr,
	    "usage: %s [--repl] [script.lua]\n"
	    "\n"
	    "  script.lua   run a Lua script (script may call repl:run() itself)\n"
	    "  --repl       start the REPL after the script (or immediately if\n"
	    "               no script is given)\n"
	    "\n"
	    "  Inside the REPL: ,help  ,quit  ctrl-D\n",
	    prog);
}

// readline
static int l_readline(lua_State *L)
{
	const char *prompt = luaL_optstring(L, 1, "");
	char *line = readline(prompt);

	if (!line) {
		lua_pushnil(L);
		return 1;
	}

	if (*line)
		add_history(line);

	lua_pushstring(L, line);
	free(line);
	return 1;
}

//
// Main
//

int main(int argc, char **argv)
{
	const char *script = NULL;
	int want_repl = 0;

	// arg parsing
	for (int i = 1; i < argc; i++) {
		if (strcmp(argv[i], "--repl") == 0) {
			want_repl = 1;
		} else if (strcmp(argv[i], "--help") == 0 ||
		           strcmp(argv[i], "-h") == 0) {
			usage(argv[0]);
			return EXIT_SUCCESS;
		} else if (argv[i][0] == '-') {
			fprintf(stderr, "unknown option: %s\n", argv[i]);
			usage(argv[0]);
			return EXIT_FAILURE;
		} else if (!script) {
			script = argv[i];
		} else {
			fprintf(stderr, "too many arguments\n");
			usage(argv[0]);
			return EXIT_FAILURE;
		}
	}

	if (!script && !want_repl) {
		usage(argv[0]);
		return EXIT_FAILURE;
	}

	// Lua initialisation
	lua_State *L = luaL_newstate();
	if (!L) {
		fprintf(stderr, "failed to create Lua state\n");
		return EXIT_FAILURE;
	}

	luaL_openlibs(L);
	set_lua_path(L);
	register_preloaders(L);

	rl_instream = stdin;
	rl_outstream = stdout;
	lua_pushcfunction(L, l_readline);
	lua_setglobal(L, "readline");

	// run user script
	if (script) {
		const char *ext = strrchr(script, '.');

		int is_fennel = ext && strcmp(ext, ".fnl") == 0;
		int is_lua = ext && strcmp(ext, ".lua") == 0;

		lua_pushstring(L, script);
		lua_setglobal(L, "_script");

		if (is_fennel) {
			lua_getglobal(L, "require");
			lua_pushstring(L, "fennel");
			lua_call(L, 1, 1);
			lua_getfield(L, -1, "dofile");
			lua_pushstring(L, script);
			if (lua_pcall(L, 1, 0, 0) != LUA_OK) {
				fprintf(stderr, "error running fennel script: %s\n",
				        lua_tostring(L, -1));
				lua_close(L);
				return EXIT_FAILURE;
			}
		} else if (is_lua) {
			if (luaL_dofile(L, script) != LUA_OK) {
				fprintf(stderr, "error running script: %s\n",
				        lua_tostring(L, -1));
				lua_close(L);
				return EXIT_FAILURE;
			}
		}

		fprintf(stderr, "error: script must be a .lua or .fnl file\n");
		lua_close(L);
		return EXIT_FAILURE;
	}

	// bare REPL
	if (want_repl) {
		const char *boot = "local REPL = require('jnl.repl')\n"
		                   "local repl = REPL.new()\n"
		                   "repl:run()\n";

		if (luaL_dostring(L, boot) != LUA_OK) {
			fprintf(stderr, "error starting REPL: %s\n", lua_tostring(L, -1));
			lua_close(L);
			return EXIT_FAILURE;
		}
	}

	lua_close(L);
	return EXIT_SUCCESS;
}
