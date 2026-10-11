// SPDX-License-Identifier: CDDL-1.0
//
// Minimal reproducer for the kernel bug behind
// rsend/send-c_stream_size_estimate: splice(2) with a NULL output
// offset latches ->f_pos on entry and writes it back on return -- even
// when it transfers zero bytes. A splice that blocks on an empty pipe,
// never gets any data, and returns 0 still rewinds the file position
// to what it was before it blocked, clobbering whatever the file's
// other writer did while it slept.
//
// This is deliberately the same shape as lzc_send_wrapper(): one
// thread relays a pipe into a regular file with
// splice(fd_in, NULL, fd_out, NULL, ...), while the caller's own
// thread writes directly to the same fd. A dry run relays nothing, so
// the relay's zero-byte return rewinds the fd and the caller's two
// writes land on top of each other -- exactly the "full"/"size" line
// corruption `zfs send -nP` produces.
//
// Not a race in the usual sense: given the ordering below (relay
// enters splice() and blocks before the first write happens), this is
// fully deterministic on an affected kernel. No looping needed.
//
// Expected (correct kernel): final size == strlen(A) + strlen(B),
// content "AAAA...A\nBBBB...B\n" in order.
// Observed (buggy kernel): size stays at strlen(A) (or less), content
// is B's line overwriting the start of A's.
//
// Build: cc -O2 -Wall -o splice_fpos_zero_byte splice_fpos_zero_byte.c -lpthread
#define _GNU_SOURCE
#include <fcntl.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#define LINE_A "full\tsrp/fs@snap1\t8416880\n"
#define LINE_B "size\t8416880\n"

static int pfd[2];
static int outfd;

static void *relay(void *arg)
{
	(void)arg;
	// Same call lzc_send_wrapper()'s send_worker() makes: implicit
	// (NULL) output offset. Blocks in the kernel's
	// pipe_wait_readable() until the pipe's write end closes, having
	// already latched outfd's f_pos on entry.
	ssize_t n = splice(pfd[0], NULL, outfd, NULL, 1 << 16, 0);
	printf("relay: splice() returned %zd (0 = transferred nothing)\n", n);
	return NULL;
}

int main(void)
{
	char path[] = "/tmp/splice_fpos_zero_byte.XXXXXX";

	outfd = mkstemp(path);
	if (outfd < 0 || pipe(pfd)) { perror("setup"); return 1; }

	pthread_t t;
	pthread_create(&t, NULL, relay, NULL);

	usleep(200000); // let the relay thread reach splice() and block
	                 // there before outfd's position moves

	if (write(outfd, LINE_A, strlen(LINE_A)) != (ssize_t)strlen(LINE_A)) {
		perror("write A"); return 1;
	}

	close(pfd[1]); // EOF on the pipe: the relay sees no data and no
	               // writers, and returns 0 -- transferring nothing

	pthread_join(t, NULL);

	if (write(outfd, LINE_B, strlen(LINE_B)) != (ssize_t)strlen(LINE_B)) {
		perror("write B"); return 1;
	}

	struct stat st;
	fstat(outfd, &st);
	size_t expect = strlen(LINE_A) + strlen(LINE_B);
	printf("final size=%lld (expect %zu)\n", (long long)st.st_size, expect);

	char buf[128] = {0};
	pread(outfd, buf, sizeof(buf) - 1, 0);
	printf("content: %s", buf);
	printf("%s\n", (size_t)st.st_size == expect &&
	       !strncmp(buf, LINE_A LINE_B, strlen(LINE_A LINE_B)) ?
	       "OK" : "CORRUPT -- kernel splice(2) rewound the file position");

	close(outfd);
	unlink(path);
	return 0;
}
