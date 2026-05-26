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

# vendor/Triangle via CMake
TRIANGLE_SRC_DIR   := vendor/Triangle/src
TRIANGLE_BUILD_DIR := $(OBJDIR)/vendor/Triangle-cmake

TRIANGLE_CORE_LIB := $(TRIANGLE_BUILD_DIR)/Triangle/libtriangle.a
TRIANGLE_API_LIB  := $(TRIANGLE_BUILD_DIR)/Triangle/libtriangle-api.a
TRIANGLE_LIBS     := $(TRIANGLE_API_LIB) $(TRIANGLE_CORE_LIB)

TRIANGLE_INC_DIR := $(TRIANGLE_SRC_DIR)/Triangle
TRIANGLE_GEN_DIR := $(TRIANGLE_BUILD_DIR)/Triangle

ifeq ($(BUILD), release)
	TRIANGLE_CMAKE_BUILD_TYPE := Release
else
	TRIANGLE_CMAKE_BUILD_TYPE := Debug
endif

# vendor/fennel
FENNEL_VENDOR_DIR := vendor/fennel
FENNEL_DST        := $(LUADIR)/fennel.lua

# compiler vars
CC = gcc
CFLAGS_LUA := $(shell pkg-config --cflags lua5.5) \
				-DLUA_ASSET_PATH='"$(LUADIR)"'

CFLAGS_COMMON := -Wall -pedantic -MMD -MP \
				-I$(HDIR) \
				-I$(TRIANGLE_INC_DIR) \
				-I$(TRIANGLE_GEN_DIR) \
				$(CFLAGS_LUA)

CFLAGS_DEBUG := -O0 -g3
CFLAGS_RELEASE := -O3 -march=native -flto -ffast-math -DNDEBUG

ifeq ($(BUILD), release)
	CFLAGS := $(CFLAGS_COMMON) $(CFLAGS_RELEASE)
else
	CFLAGS := $(CFLAGS_COMMON) $(CFLAGS_DEBUG)
endif

LDFLAGS_LUA := $(shell pkg-config --libs lua5.5)
LDFLAGS_TEST := -lm
LDFLAGS := -lraylib $(LDFLAGS_LUA) -lm -lreadline

# src/ vars
SRCS := $(shell find $(SRCDIR) -name '*.c')
OBJS := $(patsubst $(SRCDIR)/%.c, $(OBJDIR)/%.o, $(SRCS))
DEPS := $(OBJS:.o=.d)

# cmd/ vars
CMD_DIRS := $(wildcard $(CMDDIR)/*)
CMD_BINS := $(patsubst $(CMDDIR)/%, $(BINDIR)/%, $(CMD_DIRS))
CMD_SRCS := $(foreach dir, $(CMD_DIRS), $(wildcard $(dir)/*.c))
CMD_OBJS := $(patsubst $(CMDDIR)/%.c, $(OBJDIR)/$(CMDDIR)/%.o, $(CMD_SRCS))
DEPS     += $(CMD_OBJS:.o=.d)

# test/ vars
TEST_SRCS     := $(wildcard $(TESTDIR)/*.c)
TEST_BINS     := $(patsubst $(TESTDIR)/%.c, $(BINDIR)/test/%, $(TEST_SRCS))
TEST_OBJS     := $(patsubst $(TESTDIR)/%.c, $(OBJDIR)/test/%.o, $(TEST_SRCS))
TEST_LIB_SRCS := $(filter-out %_lua.c $(SRCDIR)/ui.c $(SRCDIR)/ui_%.c, $(SRCS))
TEST_LIB_OBJS := $(patsubst $(SRCDIR)/%.c, $(OBJDIR)/%.o, $(TEST_LIB_SRCS))
DEPS          += $(TEST_OBJS:.o=.d)

# verbosity: make V=1 for full commands
V ?= 0
ifeq ($(V), 0)
	Q := @
	LOG_CC = @printf "  CC    %s\n" $@
	LOG_LD = @printf "  LD    %s\n" $@
	LOG_CMAKE = @printf "  CMAKE %s \n" $(TRIANGLE_BUILD_DIR)
else
	Q :=
	LOG_CC :=
	LOG_LD :=
	LOG_CMAKE :=
endif

.PHONY: all clean test release debug triangle llm

all: $(FENNEL_DST) $(CMD_BINS)

debug:
	$(MAKE) BUILD=debug all

release:
	$(MAKE) BUILD=release all

triangle: $(TRIANGLE_LIBS)

test: $(TEST_BINS)
	@failed=0; \
	for t in $(TEST_BINS); do \
		printf "running %-40s \n" $$t; \
		if $$t; then echo "OK"; else echo "FAILED"; failed=1; fi; \
	done; \
	exit $$failed

#
# Triangle CMake build
#

$(TRIANGLE_CORE_LIB) $(TRIANGLE_API_LIB):
	$(LOG_CMAKE)
	$(Q)mkdir -p $(TRIANGLE_BUILD_DIR)
	$(Q)cmake -S $(TRIANGLE_SRC_DIR) \
	      -B $(TRIANGLE_BUILD_DIR) \
	      -DCMAKE_BUILD_TYPE=$(TRIANGLE_CMAKE_BUILD_TYPE) \
	      -DBUILD_SHARED_LIBS=OFF \
	      -DBUILD_TESTING=OFF \
	      -DBUILD_EXAMPLES=OFF \
	      -DTRIANGLE_ENABLE_ACUTE=ON
	$(Q)cmake --build $(TRIANGLE_BUILD_DIR)
	@for lib in $(TRIANGLE_LIBS); do \
		objcopy --redefine-sym readline=triangle_readline \
		        --redefine-sym writeline=triangle_writeline \
		        $$lib; \
	done

#
# test/ build
#

$(BINDIR)/test/%: $(OBJDIR)/test/%.o $(TEST_LIB_OBJS) $(TRIANGLE_LIBS) | $(BINDIR)/test
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
# cmd/ build
#

$(BINDIR)/%: $(OBJDIR)/$(CMDDIR)/%/main.o \
             $(filter-out $(OBJDIR)/$(CMDDIR)/$*/main.o, \
               $(filter $(OBJDIR)/$(CMDDIR)/$*/%.o, $(CMD_OBJS))) \
             $(OBJS) \
             $(TRIANGLE_LIBS) | $(BINDIR) $(OUTDIR)
	$(LOG_LD)
	$(Q)$(CC) $(CFLAGS) -o $@ \
		$(OBJDIR)/$(CMDDIR)/$*/main.o \
		$(filter-out $(OBJDIR)/$(CMDDIR)/$*/main.o, \
		  $(filter $(OBJDIR)/$(CMDDIR)/$*/%.o, $(CMD_OBJS))) \
		$(OBJS) \
		$(TRIANGLE_LIBS) \
		$(LDFLAGS)

$(OBJDIR)/$(CMDDIR)/%.o: $(CMDDIR)/%.c | $(TRIANGLE_LIBS)
	@mkdir -p $(dir $@)
	$(LOG_CC)
	$(Q)$(CC) $(CFLAGS) -c -o $@ $<

#
# src/ build
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
	$(Q)$(MAKE) -C $(FENNEL_VENDOR_DIR) fennel.lua LUA=lua5.5
	$(Q)cp $(FENNEL_VENDOR_DIR)/fennel.lua $@

$(LUADIR):
	mkdir -p $@

#
# LLM context
#

LLM_SRCS := $(shell find $(LUADIR) -name '*.lua')

AGENTS.md: $(LLM_SRCS) | $(BINDIR)/cli
	@printf "  LLM   %s\n" $@
	$(Q)$(BINDIR)/cli --llm > $@

llm: AGENTS.md

#
# dirs
#

$(BINDIR):
	mkdir -p $@

$(BINDIR)/test:
	mkdir -p $@

$(OUTDIR):
	mkdir -p $@

-include $(DEPS)

clean:
	rm -rf build bin $(OUTDIR) $(FENNEL_DST)
