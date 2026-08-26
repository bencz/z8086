#include <cerrno>
#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <fcntl.h>
#include <termios.h>
#include <unistd.h>

namespace {
termios saved_termios{};
int saved_flags = 0;
bool terminal_active = false;

void restore_terminal() {
    if (!terminal_active) return;
    tcsetattr(STDIN_FILENO, TCSANOW, &saved_termios);
    fcntl(STDIN_FILENO, F_SETFL, saved_flags);
    terminal_active = false;
}

void handle_signal(int signal_number) {
    restore_terminal();
    std::signal(signal_number, SIG_DFL);
    std::raise(signal_number);
}
}  // namespace

extern "C" int host_terminal_init() {
    if (!isatty(STDIN_FILENO) || tcgetattr(STDIN_FILENO, &saved_termios) != 0)
        return 0;

    termios interactive = saved_termios;
    interactive.c_lflag &= static_cast<tcflag_t>(~(ICANON | ECHO));
    interactive.c_cc[VMIN] = 0;
    interactive.c_cc[VTIME] = 0;
    if (tcsetattr(STDIN_FILENO, TCSANOW, &interactive) != 0) return 0;

    saved_flags = fcntl(STDIN_FILENO, F_GETFL, 0);
    if (saved_flags < 0 ||
        fcntl(STDIN_FILENO, F_SETFL, saved_flags | O_NONBLOCK) != 0) {
        tcsetattr(STDIN_FILENO, TCSANOW, &saved_termios);
        return 0;
    }

    terminal_active = true;
    std::atexit(restore_terminal);
    std::signal(SIGINT, handle_signal);
    std::signal(SIGTERM, handle_signal);
    setvbuf(stdout, nullptr, _IONBF, 0);
    return 1;
}

extern "C" int host_poll_key() {
    unsigned char key = 0;
    const ssize_t count = read(STDIN_FILENO, &key, 1);
    if (count == 1) return key;
    if (count < 0 && errno != EAGAIN && errno != EWOULDBLOCK) return -2;
    return -1;
}

extern "C" void host_terminal_restore() {
    restore_terminal();
}
