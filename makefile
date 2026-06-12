# filesystem vars
CMDDIR  = cmd
SRCDIR  = src
HDIR    = include
TESTDIR = test
LUADIR  = lua
OUTDIR  = out

BUILD ?= debug

BUILDDIR = build/$(BUILD)
BINDIR   = bin/$(BUILD)
OBJDIR   = $(BUILDDIR)

#
# Vendor: Triangle via CMake
#

TRIANGLE_SRC_DIR   := vendor/Triangle/src
TRIANGLE_BUILD_DIR := $(OBJDIR)/vendor/Triangle-cmake

TRIANGLE_CORE_LIB := $(TRIANGLE_BUILD_DIR)/Triangle/libtriangle.a
TRIANGLE_API_LIB  := $(TRIANGLE_BUILD_DIR)/Triangle/libtriangle-api.a
TRIANGLE_LIBS     := $(TRIANGLE_API_LIB) $(TRIANGLE_CORE_LIB)

TRIANGLE_INC_DIR := $(TRIANGLE_SRC_DIR)/Triangle
TRIANGLE_GEN_DIR := $(TRIANGLE_BUILD_DIR)/Triangle

ifeq ($(BUILD),release)
	TRIANGLE_CMAKE_BUILD_TYPE := Release
else
	TRIANGLE_CMAKE_BUILD_TYPE := Debug
endif

#
# Vendor: Fennel
#

FENNEL_VENDOR_DIR := vendor/fennel
FENNEL_DST        := $(LUADIR)/fennel.lua

#
# Compiler
#

CC = gcc

CFLAGS_LUA := \
	$(shell pkg-config --cflags lua5.5) \
	-DLUA_ASSET_PATH='"$(LUADIR)"'

CFLAGS_COMMON := \
	-Wall \
	-pedantic \
	-MMD \
	-MP \
	-I$(HDIR) \
	-I$(TRIANGLE_INC_DIR) \
	-I$(TRIANGLE_GEN_DIR) \
	$(CFLAGS_LUA)

CFLAGS_DEBUG := \
	-O0 \
	-g3

CFLAGS_RELEASE := \
	-O3 \
	-march=native \
	-flto=auto \
	-ffast-math \
	-DNDEBUG

ifeq ($(BUILD),release)
	CFLAGS := $(CFLAGS_COMMON) $(CFLAGS_RELEASE)
else
	CFLAGS := $(CFLAGS_COMMON) $(CFLAGS_DEBUG)
endif

LDFLAGS_LUA  := $(shell pkg-config --libs lua5.5)
LDFLAGS_TEST := -lm
LDFLAGS      := -lraylib $(LDFLAGS_LUA) -lm -lreadline

#
# Host backend
#

HOST_BACKEND ?=

ifeq ($(strip $(HOST_BACKEND)),)
	ifeq ($(OS),Windows_NT)
		HOST_BACKEND := win32
	else ifneq ($(findstring emcc,$(notdir $(CC))),)
		HOST_BACKEND := emscripten
	else
		HOST_BACKEND := posix
	endif
endif

HOST_BACKENDS := posix win32 emscripten

HOST_ALL_SRCS := $(sort $(shell find $(SRCDIR)/host -name '*.c'))

HOST_BACKEND_SRCS := $(addprefix $(SRCDIR)/host/,$(addsuffix .c,$(HOST_BACKENDS)))

HOST_COMMON_SRCS := $(filter-out $(HOST_BACKEND_SRCS),$(HOST_ALL_SRCS))

HOST_BACKEND_SRC := $(SRCDIR)/host/$(HOST_BACKEND).c

ifeq ($(wildcard $(HOST_BACKEND_SRC)),)
	$(error Host backend source not found: $(HOST_BACKEND_SRC))
endif

#
# src/
#

ALL_SRCS := $(sort $(shell find $(SRCDIR) -name '*.c'))

SRCS := \
	$(filter-out $(SRCDIR)/host/%.c,$(ALL_SRCS)) \
	$(HOST_COMMON_SRCS) \
	$(HOST_BACKEND_SRC)

OBJS := $(patsubst $(SRCDIR)/%.c,$(OBJDIR)/%.o,$(SRCS))
DEPS := $(OBJS:.o=.d)

#
# cmd/
#

CMD_DIRS  := $(wildcard $(CMDDIR)/*)
CMD_NAMES := $(notdir $(CMD_DIRS))
CMD_BINS  := $(addprefix $(BINDIR)/,$(CMD_NAMES))

CMD_SRCS := $(foreach dir,$(CMD_DIRS),$(wildcard $(dir)/*.c))
CMD_OBJS := $(patsubst $(CMDDIR)/%.c,$(OBJDIR)/$(CMDDIR)/%.o,$(CMD_SRCS))

DEPS += $(CMD_OBJS:.o=.d)

cmd_sources = $(wildcard $(CMDDIR)/$(1)/*.c)
cmd_objects = $(patsubst $(CMDDIR)/%.c,$(OBJDIR)/$(CMDDIR)/%.o,$(call cmd_sources,$(1)))

#
# test/
#

TEST_RUNNER := scripts/test_runner.sh

TEST_SRCS := $(sort $(shell find $(TESTDIR) -name '*_test.c'))
TEST_BINS := $(patsubst $(TESTDIR)/%.c,$(BINDIR)/test/%,$(TEST_SRCS))
TEST_OBJS := $(patsubst $(TESTDIR)/%.c,$(OBJDIR)/test/%.o,$(TEST_SRCS))

TEST_LIB_SRCS := $(filter-out \
	%_lua.c \
	$(SRCDIR)/ui.c \
	$(SRCDIR)/ui_%.c \
	$(SRCDIR)/ui/%.c, \
	$(SRCS))

TEST_LIB_OBJS := $(patsubst $(SRCDIR)/%.c,$(OBJDIR)/%.o,$(TEST_LIB_SRCS))

DEPS += $(TEST_OBJS:.o=.d)

#
# Verbosity
#
# Use `make V=1` for full commands.
#

V ?= 0

ifeq ($(V),0)
	Q := @

	LOG_CC    = @printf "  CC    %s\n" $@
	LOG_LD    = @printf "  LD    %s\n" $@
	LOG_CMAKE = @printf "  CMAKE %s\n" $(TRIANGLE_BUILD_DIR)
else
	Q :=

	LOG_CC :=
	LOG_LD :=
	LOG_CMAKE :=
endif

#
# Top-level targets
#

.PHONY: \
	all \
	clean \
	test \
	c-test \
	lua-test \
	release \
	debug \
	triangle \
	llm

all: $(FENNEL_DST) $(CMD_BINS)

debug:
	$(MAKE) BUILD=debug all

release:
	$(MAKE) BUILD=release all

triangle: $(TRIANGLE_LIBS)

test: $(TEST_BINS) $(BINDIR)/cli
	@failed=0; \
	printf "\nC TESTS\n"; \
	$(TEST_RUNNER) $(TEST_BINS) || failed=1; \
	printf "\nLUA TESTS\n"; \
	$(BINDIR)/cli lua/test/init.lua || failed=1; \
	exit $$failed

c-test: $(TEST_BINS)
	@printf "\nC TESTS\n"
	@$(TEST_RUNNER) $(TEST_BINS)

lua-test: $(BINDIR)/cli
	@printf "\nLUA TESTS\n"
	$(Q)$(BINDIR)/cli lua/test/init.lua

#
# Triangle CMake build
#

$(TRIANGLE_CORE_LIB) $(TRIANGLE_API_LIB) &:
	$(LOG_CMAKE)
	$(Q)mkdir -p $(TRIANGLE_BUILD_DIR)
	$(Q)cmake \
		-S $(TRIANGLE_SRC_DIR) \
		-B $(TRIANGLE_BUILD_DIR) \
		-DCMAKE_BUILD_TYPE=$(TRIANGLE_CMAKE_BUILD_TYPE) \
		-DBUILD_SHARED_LIBS=OFF \
		-DBUILD_TESTING=OFF \
		-DBUILD_EXAMPLES=OFF \
		-DTRIANGLE_ENABLE_ACUTE=ON
	$(Q)cmake --build $(TRIANGLE_BUILD_DIR) \
		--config $(TRIANGLE_CMAKE_BUILD_TYPE)
	@for lib in $(TRIANGLE_LIBS); do \
		objcopy \
			--redefine-sym readline=triangle_readline \
			--redefine-sym writeline=triangle_writeline \
			$$lib; \
	done

#
# Test build
#

$(BINDIR)/test/%: \
	$(OBJDIR)/test/%.o \
	$(TEST_LIB_OBJS) \
	$(TRIANGLE_LIBS)
	@mkdir -p $(dir $@)
	$(LOG_LD)
	$(Q)$(CC) $(CFLAGS) -o $@ \
		$(OBJDIR)/test/$*.o \
		$(TEST_LIB_OBJS) \
		$(TRIANGLE_LIBS) \
		$(LDFLAGS_TEST)

$(OBJDIR)/test/%.o: $(TESTDIR)/%.c | $(TRIANGLE_LIBS)
	@mkdir -p $(dir $@)
	$(LOG_CC)
	$(Q)$(CC) $(CFLAGS) -c -o $@ $<

#
# Command build
#

define COMMAND_template

$(BINDIR)/$(1): $(call cmd_objects,$(1)) $(OBJS) $(TRIANGLE_LIBS) | $(BINDIR) $(OUTDIR)
	$$(LOG_LD)
	$$(Q)$$(CC) $$(CFLAGS) -o $$@ \
		$(call cmd_objects,$(1)) \
		$$(OBJS) \
		$$(TRIANGLE_LIBS) \
		$$(LDFLAGS)

endef

$(foreach command,$(CMD_NAMES),$(eval $(call COMMAND_template,$(command))))

$(OBJDIR)/$(CMDDIR)/%.o: $(CMDDIR)/%.c | $(TRIANGLE_LIBS)
	@mkdir -p $(dir $@)
	$(LOG_CC)
	$(Q)$(CC) $(CFLAGS) -c -o $@ $<

#
# Library source build
#

$(OBJDIR)/%.o: $(SRCDIR)/%.c | $(TRIANGLE_LIBS)
	@mkdir -p $(dir $@)
	$(LOG_CC)
	$(Q)$(CC) $(CFLAGS) -c -o $@ $<

#
# Fennel
#

$(FENNEL_DST): $(wildcard $(FENNEL_VENDOR_DIR)/src/fennel/*.fnl) | $(LUADIR)
	@printf "  FENNEL %s\n" $@
	$(Q)$(MAKE) \
		-C $(FENNEL_VENDOR_DIR) \
		fennel.lua \
		LUA=lua5.5
	$(Q)cp $(FENNEL_VENDOR_DIR)/fennel.lua $@

$(LUADIR):
	mkdir -p $@

#
# LLM context
#

LLM_SRCS := $(shell find $(LUADIR) -name '*.lua')

llm_spiel.md: $(LLM_SRCS) | $(BINDIR)/cli
	@printf "  LLM   %s\n" $@
	$(Q)$(BINDIR)/cli --llm > $@

llm: llm_spiel.md

#
# Output directories
#

$(BINDIR):
	mkdir -p $@

$(OUTDIR):
	mkdir -p $@

#
# Dependency files
#

-include $(DEPS)

#
# Cleanup
#

clean:
	rm -rf \
		build \
		bin \
		$(OUTDIR) \
		$(FENNEL_DST)
