# filesystem vars
CMDDIR  = cmd
BINDIR  = bin
SRCDIR  = src
OBJDIR  = build
HDIR    = include
TESTDIR = test
LUADIR  = lua

# compiler vars
CC = gcc
CFLAGS_LUA := $(shell pkg-config --cflags lua5.5) \
				-DLUA_ASSET_PATH='"$(LUADIR)"'
CFLAGS := -g -Wall -pedantic -MMD -MP -I$(HDIR) $(CFLAGS_LUA)

LDFLAGS_LUA := $(shell pkg-config --libs lua5.5)
LDFLAGS_TEST := -lm
LDFLAGS := -lraylib -lm $(LDFLAGS_LUA)

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
TEST_LIB_OBJS := $(filter-out $(OBJDIR)/ui.o, $(OBJS))
DEPS          += $(TEST_OBJS:.o=.d)

.PHONY: all clean test

all: $(CMD_BINS)

test: $(TEST_BINS)
	@failed=0; \
	for t in $(TEST_BINS); do \
		printf "running %-40s \n" $$t; \
		if $$t; then echo "OK"; else echo "FAILED"; failed=1; fi; \
	done; \
	exit $$failed

$(BINDIR)/test/%: $(OBJDIR)/test/%.o $(TEST_LIB_OBJS) | $(BINDIR)/test
	$(CC) $(LDFLAGS_TEST) -o $@ $^

$(OBJDIR)/test/%.o: $(TESTDIR)/%.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c -o $@ $<

$(BINDIR)/%: $(OBJDIR)/$(CMDDIR)/%/main.o \
             $(filter $(OBJDIR)/$(CMDDIR)/$*/%.o, $(CMD_OBJS)) \
             $(OBJS) | $(BINDIR)
	$(CC) $(LDFLAGS) -o $@ $^

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

-include $(DEPS)

clean:
	rm -rf $(OBJDIR) $(BINDIR)
