#include "BridgingHeader.h"

int main() {
  int fd = posix_openpt(O_RDWR);
  grantpt(fd);
  unlockpt(fd);
  printf("%s\n", ptsname(fd));
}