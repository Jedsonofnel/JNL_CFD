# filesystem vars
BINDIR  = bin
SRCDIR  = src
OBJDIR  = build
HDIR    = include

# compiler vars
CC = gcc
CFLAGS := -g -Wall -pedantic -MMD -MP -I$(HDIR) -I$(OBJDIR) \
			$(shell guile-config compile)
CFLAGS_BINDINGS = $(filter-out -pedantic, $(CFLAGS))
LDFLAGS := $(shell guile-config link)

# artefact vars
BIN = $(BINDIR)/cli

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

.PHONY: all clean

all: $(BIN)

$(BIN): $(OBJS) $(BINDING_OBJS) | $(BINDIR)
	$(CC) $(LDFLAGS) -o $@ $^

# Normal C object file compilation
$(OBJDIR)/%.o: $(SRCDIR)/%.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c -o $@ $<

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

-include $(DEPS)

clean:
	rm -rf $(OBJDIR) $(BINDIR)
