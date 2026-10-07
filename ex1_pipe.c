/*
 * Lab 6 - Exercício 1: um pipe entre pai e filho.
 *
 * Rode com: ./ex1
 *
 * O pai manda três linhas para o filho por um pipe, uma por segundo,
 * fecha a sua ponta de escrita e espera o filho terminar. O filho lê do
 * pipe até a entrada acabar.
 *
 * TODO 1: o enunciado está na seção 1 do LAB06.md, depois da pergunta 1.1.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/wait.h>

int main(void)
{
    const char *linhas[] = { "primeira\n", "segunda\n", "terceira\n" };
    int fd[2];

    if (pipe(fd) < 0) {
        perror("pipe");
        return 1;
    }

    pid_t pid = fork();
    if (pid < 0) {
        perror("fork");
        return 1;
    }

    if (pid == 0) {
        /* Filho: lê do pipe até o read avisar que não vem mais nada. */
        char buf[64];
        ssize_t n;
        long total = 0;

        while ((n = read(fd[0], buf, sizeof(buf))) > 0) {
            total += n;
            fprintf(stderr, "filho: recebi %zd bytes\n", n);
        }
        fprintf(stderr, "filho: a entrada acabou, %ld bytes no total\n", total);
        exit(0);
    }

    /* Pai: escreve as três linhas e fecha a escrita. */
    close(fd[0]);
    for (int i = 0; i < 3; i++) {
        if (write(fd[1], linhas[i], strlen(linhas[i])) < 0)
            perror("write");
        fprintf(stderr, "pai: enviei a linha %d\n", i + 1);
        sleep(1);
    }
    close(fd[1]);
    fprintf(stderr, "pai: fechei a escrita, esperando o filho\n");

    wait(NULL);
    fprintf(stderr, "pai: o filho terminou\n");
    return 0;
}
