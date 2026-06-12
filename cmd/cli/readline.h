#ifndef JNL_CLI_READLINE_H
#define JNL_CLI_READLINE_H

#include <lua.h>

int jnl_cli_readline_init(lua_State *L);

void jnl_cli_readline_shutdown(void);

int jnl_cli_repl_started(void);

#endif
