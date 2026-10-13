# Stand-in for zarcsummary: same re-exec and exception handler as
# cmd/zarcsummary, then 300 lines of output. Pipe it into head under
# ksh93 (socketpair) and bash (pipe) to see ConnectionResetError.
import os, sys, io, errno
if isinstance(sys.__stderr__.buffer, io.BufferedWriter):
    os.execv(sys.executable, [sys.executable, "-u"] + sys.argv)
def handle_Exception(ex_cls, ex, tb):
    if ex_cls is KeyboardInterrupt:
        sys.exit()
    if ex_cls is BrokenPipeError:
        os._exit(0)
    if ex_cls is OSError:
        if ex.errno == errno.ENOTCONN:
            sys.exit()
    sys.stderr.write("UNHANDLED %s\n" % ex_cls.__name__)
    os._exit(1)
sys.excepthook = handle_Exception
for i in range(300):
    print('        %-40s %10d' % ('Some ARC statistic line', i))
