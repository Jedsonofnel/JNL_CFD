# filesystem vars
CMDDIR  = cmd
BINDIR  = bin
SRCDIR  = src
OBJDIR  = build
HDIR    = include
TESTDIR = test

# compiler vars
CC = gcc
CFLAGS := -g -Wall -pedantic -MMD -MP -I$(HDIR) -I$(OBJDIR) \
			$(shell guile-config compile)
CFLAGS_BINDINGS = $(filter-out -pedantic, $(CFLAGS))
LDFLAGS := $(shell guile-config link) -lraylib -lm
LDFLAGS_TEST := -lm

# src/ vars
SRCS := $(shell find $(SRCDIR) -name '*.c' \
			-not -path '$(SRCDIR)/bindings/*')
BINDING_SRCS := $(shell find $(SRCDIR)/bindings -name '*.c')
SCM_SRCS := $(shell find $(SRCDIR) -name '*.scm')

# build/ vars
OBJS := $(patsubst $(SRCDIR)/%.c, $(OBJDIR)/%.o, $(SRCS))
BINDING_OBJS := $(patsubst $(SRCDIR)/%.c, $(OBJDIR)/%.o, $(BINDING_SRCS))
XXD_HDRS := $(patsubst $(SRCDIR)/%.scm, $(OBJDIR)/%.go.h, $(SCM_SRCS))
DEPS := $(OBJS:.o=.d) $(BINDING_OBJS:.o=.d)

# cmd/ vars
CMD_DIRS    := $(wildcard $(CMDDIR)/*)
CMD_BINS    := $(patsubst $(CMDDIR)/%, $(BINDIR)/%, $(CMD_DIRS))
CMD_SRCS    := $(foreach dir, $(CMD_DIRS), $(wildcard $(dir)/*.c))
CMD_OBJS    := $(patsubst $(CMDDIR)/%.c, $(OBJDIR)/$(CMDDIR)/%.o, $(CMD_SRCS))
DEPS        += $(CMD_OBJS:.o=.d)

# test/vars
TEST_SRCS   := $(wildcard $(TESTDIR)/*.c)
TEST_BINS   := $(patsubst $(TESTDIR)/%.c, $(BINDIR)/test/%, $(TEST_SRCS))
TEST_OBJS   := $(patsubst $(TESTDIR)/%.c, $(OBJDIR)/test/%.o, $(TEST_SRCS))
TEST_LIB_OBJS := $(filter-out $(OBJDIR)/ui.o, $(OBJS))
DEPS        += $(TEST_OBJS:.o=.d)

.PHONY: all clean test
all: $(CMD_BINS)

test: $(TEST_BINS)
	@failed=0; \
	for t in $(TEST_BINS); do \
		printf "running %-40s \n" $$t; \
		if $$t; then echo "OK"; else echo "FAILED"; failed=1; fi; \
	done; \
	exit $$failed

# Link each test binary against shared objs (no guile/raylib)
$(BINDIR)/test/%: $(OBJDIR)/test/%.o $(TEST_LIB_OBJS) | $(BINDIR)/test
	$(CC) $(LDFLAGS_TEST) -o $@ $^

# Test object compilation
$(OBJDIR)/test/%.o: $(TESTDIR)/%.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c -o $@ $<

# Link each cmd binary against all shared objs
$(BINDIR)/%: $(OBJDIR)/$(CMDDIR)/%/main.o \
             $(filter $(OBJDIR)/$(CMDDIR)/$*/%.o, $(CMD_OBJS)) \
             $(OBJS) $(BINDING_OBJS) | $(BINDIR)
	$(CC) $(LDFLAGS) -o $@ $^

# cmd/ object compilation
$(OBJDIR)/$(CMDDIR)/%.o: $(CMDDIR)/%.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c -o $@ $<

# Normal C object file compilation
$(OBJDIR)/%.o: $(SRCDIR)/%.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c -o $@  $<

$(OBJDIR)/bindings/%.o: $(SRCDIR)/bindings/%.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS_BINDINGS) -c -o $@ $<

# Scheme compilation
$(OBJS) $(BINDING_OBJS): | $(XXD_HDRS)

$(OBJDIR)/%.go: $(SRCDIR)/%.scm
	@mkdir -p $(dir $@)
	guild compile -L $(SRCDIR)/bindings -o $@ $<

$(OBJDIR)/%.go.h: $(OBJDIR)/%.go
	@mkdir -p $(dir $@)
	cd $(dir $<) && xxd -i $(notdir $<) > $(abspath $@)

$(BINDIR):
	mkdir -p $@

$(BINDIR)/test:
	mkdir -p $@

-include $(DEPS)

clean:
	rm -rf $(OBJDIR) $(BINDIR)
