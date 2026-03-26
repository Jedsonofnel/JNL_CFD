# filesystem vars
BINDIR  = bin
SRCDIR  = src
OBJDIR  = build
HDIR    = include

# compiler vars
CC = gcc
CFLAGS := -g -Wall -pedantic -MMD -MP -I$(HDIR) \
			$(shell guile-config compile)
CFLAGS_BINDINGS = $(filter-out -pedantic, $(CFLAGS))
LDFLAGS := $(shell guile-config link)

# artefact vars
BIN = $(BINDIR)/cli

SRCS := $(shell find $(SRCDIR) -name '*.c' \
			-not -path '$(SRCDIR)/bindings/*')
BINDING_SRCS := $(shell find $(SRCDIR)/bindings -name '*.c')

OBJS := $(patsubst $(SRCDIR)/%.c, $(OBJDIR)/%.o, $(SRCS))
BINDING_OBJS := $(patsubst $(SRCDIR)/%.c, $(OBJDIR)/%.o, $(BINDING_SRCS))

DEPS := $(OBJS:.o=.d) $(BINDING_OBJS:.o=.d)

.PHONY: all clean

all: $(BIN)

$(BIN): $(OBJS) $(BINDING_OBJS) | $(BINDIR)
	$(CC) $(LDFLAGS) -o $@ $^

$(OBJDIR)/%.o: $(SRCDIR)/%.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c -o $@ $<

$(OBJDIR)/bindings/%.o: $(SRCDIR)/bindings/%.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS_BINDINGS) -c -o $@ $<

$(BINDIR):
	mkdir -p $@

-include $(DEPS)

clean:
	rm -rf $(OBJDIR) $(BINDIR)
