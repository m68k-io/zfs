/*
 * Read one line at a time from a pipe without over-reading, three ways:
 * one byte per read(), tee(2) peek into a scratch pipe, and
 * recv(MSG_PEEK) on a socketpair (what ksh93 does today).
 *
 * gcc -O2 -o peek peek.c && ./peek FILE bytewise|tee|sock
 *
 * Result 2026-10-13: 300000 short lines: bytewise 0.193s, tee 0.173s,
 * sock 0.086s; 100000 lines of 200 bytes: bytewise 1.433s, tee 0.052s,
 * sock 0.058s.
 */
#define _GNU_SOURCE
#include <fcntl.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static int scratch[2] = {-1, -1};

static ssize_t line_bytewise(int fd, char *buf, size_t n)
{
	size_t i = 0;
	while (i < n) {
		ssize_t r = read(fd, buf + i, 1);
		if (r <= 0)
			return i ? (ssize_t)i : r;
		if (buf[i++] == '\n')
			break;
	}
	return i;
}

static ssize_t line_peek(int fd, char *buf, size_t n, int use_tee)
{
	ssize_t r;
	if (use_tee) {
		struct pollfd p = { .fd = fd, .events = POLLIN };
		if (poll(&p, 1, -1) < 0)
			return -1;
		r = tee(fd, scratch[1], n, SPLICE_F_NONBLOCK);
		if (r > 0 && read(scratch[0], buf, r) != r)
			return -1;
	} else {
		r = recv(fd, buf, n, MSG_PEEK);
	}
	if (r <= 0)
		return r;
	char *nl = memchr(buf, '\n', r);
	size_t want = nl ? (size_t)(nl - buf + 1) : (size_t)r;
	return read(fd, buf, want);	/* consume exactly one line */
}

int main(int argc, char **argv)
{
	int pv[2];
	const char *m = argv[2];
	if (!strcmp(m, "sock"))
		socketpair(AF_UNIX, SOCK_STREAM, 0, pv);
	else
		pipe(pv);
	pipe2(scratch, O_CLOEXEC);
	if (fork() == 0) {
		close(pv[0]);
		int in = open(argv[1], O_RDONLY);
		char b[65536];
		ssize_t r;
		while ((r = read(in, b, sizeof b)) > 0)
			if (write(pv[1], b, r) != r)
				_exit(1);
		_exit(0);
	}
	close(pv[1]);
	struct timespec a, z;
	clock_gettime(CLOCK_MONOTONIC, &a);
	char buf[8192];
	long lines = 0, bytes = 0;
	ssize_t r;
	while ((r = !strcmp(m, "bytewise") ? line_bytewise(pv[0], buf, sizeof buf)
	           : line_peek(pv[0], buf, sizeof buf, !strcmp(m, "tee"))) > 0) {
		lines++;
		bytes += r;
	}
	clock_gettime(CLOCK_MONOTONIC, &z);
	wait(NULL);
	printf("%-8s lines=%ld bytes=%ld %.3fs\n", m, lines, bytes,
	    (z.tv_sec - a.tv_sec) + (z.tv_nsec - a.tv_nsec) / 1e9);
	return 0;
}
