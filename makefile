# filesystem vars
BINDIR  = bin
SRCDIR  = src
OBJDIR  = build
HDIR    = include

# compiler vars
CC      = gcc
CFLAGS  = -g -Wall -pedantic -MMD -MP -I$(HDIR)
LDFLAGS =

# artefact vars
BIN  = $(BINDIR)/cli
SRCS := $(shell find $(SRCDIR) -name '*.c')
OBJS := $(patsubst $(SRCDIR)/%.c, $(OBJDIR)/%.o, $(SRCS))
DEPS := $(OBJS:.o=.d)

.PHONY: all clean

all: $(BIN)

$(BIN): $(OBJS) | $(BINDIR)
	$(CC) $(LDFLAGS) -o $@ $^

$(OBJDIR)/%.o: $(SRCDIR)/%.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c -o $@ $<

$(BINDIR):
	mkdir -p $@

-include $(DEPS)

clean:
	rm -rf $(OBJDIR) $(BINDIR)
