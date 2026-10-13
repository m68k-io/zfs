/*
 * Proposed addition to ksh93's pipe_socketpair feature test
 * (src/cmd/ksh93/features/poll): does a writer blocked on a full
 * socketpair get SIGPIPE, as with a pipe, when the reader closes with
 * unread data? Exit 0 if yes, 2 if it gets ECONNRESET instead.
 *
 * Result 2026-10-13, Linux 7.1.5: 50/50 runs exit 2.
 */
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <unistd.h>

static void handler(int sig)
{
	(void)sig;
	_exit(0);
}

int main(void)
{
	int sfd[2], sync[2], status;
	static char buf[4096];
	pid_t pid;
	if (socketpair(AF_UNIX, SOCK_STREAM, 0, sfd) < 0 ||
	    shutdown(sfd[1], SHUT_RD) < 0 || shutdown(sfd[0], SHUT_WR) < 0 ||
	    pipe(sync) < 0)
		return 1;
	if ((pid = fork()) < 0)
		return 1;
	if (pid == 0) {
		close(sfd[0]);
		close(sync[0]);
		signal(SIGPIPE, handler);
		/* Fill the buffer, then block in a write. */
		fcntl(sfd[1], F_SETFL, O_NONBLOCK);
		while (write(sfd[1], buf, sizeof(buf)) > 0)
			;
		fcntl(sfd[1], F_SETFL, 0);
		close(sync[1]);
		for (;;)
			if (write(sfd[1], buf, sizeof(buf)) < 0)
				_exit(errno == ECONNRESET ? 2 : 3);
	}
	close(sfd[1]);
	close(sync[1]);
	read(sync[0], buf, 1);		/* writer is about to block */
	usleep(100000);
	close(sfd[0]);			/* close with unread data */
	if (waitpid(pid, &status, 0) < 0 || !WIFEXITED(status))
		return 1;
	return WEXITSTATUS(status);
}
