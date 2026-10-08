CC      = gcc
CFLAGS  = -Wall -Wextra -std=gnu11 -O0 

all: ex1 msh

ex1: ex1_pipe.c
	$(CC) $(CFLAGS) $< -o $@ $(LDFLAGS)

msh: msh.c
	$(CC) $(CFLAGS) $< -o $@ $(LDFLAGS)

clean:
	rm -f ex1 msh

.PHONY: all clean