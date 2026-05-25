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

# compiler vars
CC = gcc
CFLAGS_LUA := $(shell pkg-config --cflags lua5.5) \
				-DLUA_ASSET_PATH='"$(LUADIR)"'
CFLAGS_COMMON := -Wall -pedantic -MMD -MP -I$(HDIR) $(CFLAGS_LUA)

CFLAGS_DEBUG := -O0 -g3
CFLAGS_RELEASE := -O3 -march=native -flto -ffast-math -DNDEBUG

ifeq ($(BUILD), release)
	CFLAGS := $(CFLAGS_COMMON) $(CFLAGS_RELEASE)
else
	CFLAGS := $(CFLAGS_COMMON) $(CFLAGS_DEBUG)
endif

LDFLAGS_LUA := $(shell pkg-config --libs lua5.5)
LDFLAGS_TEST := -lm
LDFLAGS := -lraylib $(LDFLAGS_LUA) -lm

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

.PHONY: all clean test release debug

all: $(CMD_BINS)

debug:
	$(MAKE) BUILD=debug all


release:
	$(MAKE) BUILD=release all

test: $(TEST_BINS)
	@failed=0; \
	for t in $(TEST_BINS); do \
		printf "running %-40s \n" $$t; \
		if $$t; then echo "OK"; else echo "FAILED"; failed=1; fi; \
	done; \
	exit $$failed

$(BINDIR)/test/%: $(OBJDIR)/test/%.o $(TEST_LIB_OBJS) | $(BINDIR)/test
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS_TEST)

$(OBJDIR)/test/%.o: $(TESTDIR)/%.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c -o $@ $<

$(BINDIR)/%: $(OBJDIR)/$(CMDDIR)/%/main.o \
             $(filter $(OBJDIR)/$(CMDDIR)/$*/%.o, $(CMD_OBJS)) \
             $(OBJS) | $(BINDIR) $(OUTDIR)
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)

$(OBJDIR)/$(CMDDIR)/%.o: $(CMDDIR)/%.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c -o $@ $<

$(OBJDIR)/%.o: $(SRCDIR)/%.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c -o $@ $<

$(BINDIR):
	mkdir -p $@

$(BINDIR)/test:
	mkdir -p $@

$(OUTDIR):
	mkdir -p $@

-include $(DEPS)

clean:
	rm -rf build bin $(OUTDIR)
