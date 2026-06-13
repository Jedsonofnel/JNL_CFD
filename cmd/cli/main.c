#include <getopt.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "lua_bindings.h"
#include "readline.h"

#ifndef LUA_ASSET_PATH
#define LUA_ASSET_PATH "../lua"
#endif

// forward declaration for luasocket
int luaopen_socket_core(lua_State *L);

//
// Lua setup
//

static void set_lua_path(lua_State *L)
{
	lua_getglobal(L, "package");
	lua_getfield(L, -1, "path");

	const char *existing = lua_tostring(L, -1);

	lua_pushfstring(L,
	                LUA_ASSET_PATH "/?.lua;" LUA_ASSET_PATH "/?/init.lua;"
	                               "%s",
	                existing ? existing : "");

	/*
	 * Stack:
	 *
	 *     package, old_path, new_path
	 */
	lua_remove(L, -2);
	lua_setfield(L, -2, "path");
	lua_pop(L, 1);
}

//
// CLI help
//

static void usage(const char *program)
{
	fprintf(
	    stderr,
	    "usage: %s [options] [script.lua|script.fnl]\n"
	    "\n"
	    "options:\n"
	    "  -r, --repl    start the REPL after the script, or immediately\n"
	    "                when no script is supplied\n"
	    "  -l, --llm     print the complete LLM coding context and API\n"
	    "                reference\n"
	    "  -h, --help    show this help\n"
	    "\n"
	    "inside the REPL:\n"
	    "  ,help         show commands and registered values\n"
	    "  ,doc          list documented modules\n"
	    "  ,llm          print the complete LLM coding context\n"
	    "  ,quit         exit the REPL\n"
	    "  Ctrl-D        exit the REPL\n"
	    "\n"
	    "Ctrl-C clears the prompt. During evaluation, press once to request\n"
	    "cooperative cancellation and twice to force a Lua cancellation.\n",
	    program);
}

//
// Lua execution
//

static const char *lua_error_string(lua_State *L)
{
	const char *message = lua_tostring(L, -1);

	return message ? message : "(non-string Lua error)";
}

static int run_lua_chunk(lua_State *L, const char *source, const char *context)
{
	if (luaL_dostring(L, source) == LUA_OK) {
		lua_settop(L, 0);
		return 1;
	}

	fprintf(stderr, "%s: %s\n", context, lua_error_string(L));

	lua_settop(L, 0);

	return 0;
}

static int run_lua_script(lua_State *L, const char *path)
{
	if (luaL_dofile(L, path) == LUA_OK) {
		lua_settop(L, 0);
		return 1;
	}

	fprintf(stderr, "error running Lua script: %s\n", lua_error_string(L));

	lua_settop(L, 0);

	return 0;
}

static int run_fennel_script(lua_State *L, const char *path)
{
	lua_getglobal(L, "require");
	lua_pushstring(L, "fennel");

	if (lua_pcall(L, 1, 1, 0) != LUA_OK) {
		fprintf(stderr, "error loading Fennel: %s\n", lua_error_string(L));

		lua_settop(L, 0);

		return 0;
	}

	/*
	 * Stack:
	 *
	 *     fennel_module
	 */
	lua_getfield(L, -1, "dofile");
	lua_pushstring(L, path);

	if (lua_pcall(L, 1, 0, 0) != LUA_OK) {
		fprintf(stderr, "error running Fennel script: %s\n",
		        lua_error_string(L));

		lua_settop(L, 0);

		return 0;
	}

	lua_pop(L, 1);
	lua_settop(L, 0);

	return 1;
}

static int run_script(lua_State *L, const char *path)
{
	const char *extension = strrchr(path, '.');

	if (extension && strcmp(extension, ".lua") == 0) {
		return run_lua_script(L, path);
	}

	if (extension && strcmp(extension, ".fnl") == 0) {
		return run_fennel_script(L, path);
	}

	fprintf(stderr, "error: script must be a .lua or .fnl file\n");

	return 0;
}

//
// Main
//

int main(int argc, char **argv)
{
	const char *script = NULL;

	int want_repl = 0;
	int want_llm = 0;
	int status = EXIT_SUCCESS;

	static const struct option long_options[] = {
	    {"repl", no_argument, NULL, 'r'},
	    {"llm", no_argument, NULL, 'l'},
	    {"help", no_argument, NULL, 'h'},
	    {NULL, 0, NULL, 0},
	};

	opterr = 0;

	for (;;) {
		int option = getopt_long(argc, argv, "rlh", long_options, NULL);

		if (option == -1) {
			break;
		}

		switch (option) {
		case 'r':
			want_repl = 1;
			break;

		case 'l':
			want_llm = 1;
			break;

		case 'h':
			usage(argv[0]);
			return EXIT_SUCCESS;

		case '?':
		default:
			fprintf(stderr, "unknown option: %s\n", argv[optind - 1]);

			usage(argv[0]);

			return EXIT_FAILURE;
		}
	}

	if (optind < argc) {
		script = argv[optind++];
	}

	if (optind < argc) {
		fprintf(stderr, "too many script arguments\n");

		usage(argv[0]);

		return EXIT_FAILURE;
	}

	if (!script && !want_repl && !want_llm) {
		usage(argv[0]);
		return EXIT_FAILURE;
	}

	lua_State *L = luaL_newstate();

	if (!L) {
		fprintf(stderr, "failed to create Lua state\n");

		return EXIT_FAILURE;
	}

	luaL_openlibs(L);
	set_lua_path(L);
	register_preloaders(L);

	lua_getglobal(L, "package");
	lua_getfield(L, -1, "preload");
	lua_pushcfunction(L, luaopen_socket_core);
	lua_setfield(L, -2, "socket.core");
	lua_pop(L, 2);

	if (jnl_cli_readline_init(L) != 0) {
		perror("failed to initialise terminal input");
		status = EXIT_FAILURE;
		goto cleanup;
	}

	if (script) {
		lua_pushstring(L, script);
		lua_setglobal(L, "_script");

		lua_createtable(L, 0, 1);
		lua_pushstring(L, script);
		lua_rawseti(L, -2, 0);
		lua_setglobal(L, "arg");

		if (!run_script(L, script)) {
			status = EXIT_FAILURE;
			goto cleanup;
		}
	}

	if (want_llm) {
		const char *source = "local llm = require('jnl.doc.llm')\n"
		                     "io.write(llm.context_string({ width = 88 }))\n";

		if (!run_lua_chunk(L, source, "error generating LLM context")) {
			status = EXIT_FAILURE;
			goto cleanup;
		}

		if (!want_repl) {
			goto cleanup;
		}
	}

	if (want_repl && !jnl_cli_repl_started()) {
		/*
		 * Use the process-wide default REPL. This preserves globals and
		 * values registered by a script through require("jnl.repl").
		 */
		const char *source = "require('jnl.repl').run()\n";

		if (!run_lua_chunk(L, source, "error starting REPL")) {
			status = EXIT_FAILURE;
			goto cleanup;
		}
	}

cleanup:
	jnl_cli_readline_shutdown();
	lua_close(L);

	return status;
}
