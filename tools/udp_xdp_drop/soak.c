#include <fcntl.h>
#include <stdint.h>
#include <sys/mman.h>
#include <unistd.h>

/* soak <파일> : CPU를 받은 만큼 카운터를 올린다. 다른 CPU에서 파일을 읽어 초당 증가량을 본다 */
int main(int argc, char **argv) {
    int fd = open(argv[1], O_RDWR | O_CREAT | O_TRUNC, 0644);
    if (ftruncate(fd, sizeof(uint64_t)))
        return 1;
    volatile uint64_t *cnt = mmap(NULL, sizeof(uint64_t), PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    for (;;)
        (*cnt)++;
}
