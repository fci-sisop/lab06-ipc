/*
 * Lab 6 - msh, o mini-shell (continuação do Lab 3).
 *
 * O que já está pronto: tudo do Lab 3 (prompt, parser, 'exit', execução de
 * um comando, redirecionamento com '>') e a separação da linha no '|'.
 *
 * O que falta:
 *   TODO 2 (em sala):    executar_pipe(), para que  esq | dir  funcione.
 *   TODO 3 (conclusão):  Ctrl-C encerra o comando em execução e o msh
 *                        continua vivo.
 * O enunciado dos dois está no LAB06.md.
 */
#define _DEFAULT_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/wait.h>

#define MAX_LINHA 1024
#define MAX_ARGS    64

/*
 * Divide a linha em tokens separados por espaço, tab ou quebra de linha e
 * preenche argv, terminando com NULL (formato exigido pelo execvp).
 * Devolve a quantidade de tokens.
 */
static int parse(char *linha, char *argv[])
{
    int argc = 0;
    char *tok = strtok(linha, " \t\n");

    while (tok != NULL && argc < MAX_ARGS - 1) {
        argv[argc++] = tok;
        tok = strtok(NULL, " \t\n");
    }
    argv[argc] = NULL;
    return argc;
}

/* Devolve a posição do primeiro token igual a simbolo, ou -1. */
static int achar(char *argv[], const char *simbolo)
{
    for (int i = 0; argv[i] != NULL; i++)
        if (strcmp(argv[i], simbolo) == 0)
            return i;
    return -1;
}

/*
 * Roda no filho, antes da troca de imagem. Se o comando tiver "> arquivo",
 * o descritor 1 passa a ser o arquivo e os dois tokens saem de argv.
 * É a solução da última parte do Lab 3.
 */
static void redirecionar_saida(char *argv[])
{
    int i = achar(argv, ">");

    if (i < 0)
        return;
    if (argv[i + 1] == NULL) {
        fprintf(stderr, "msh: falta o nome do arquivo depois de >\n");
        exit(1);
    }
    close(1);
    if (open(argv[i + 1], O_WRONLY | O_CREAT | O_TRUNC, 0644) < 0) {
        perror("msh");
        exit(1);
    }
    argv[i] = NULL;
}

/*
 * Troca a imagem do processo atual pelo comando em argv, aplicando o '>'
 * se houver. Só volta se a troca falhar, e nesse caso encerra o processo.
 */
static void trocar_imagem(char *argv[])
{
    redirecionar_saida(argv);
    execvp(argv[0], argv);
    perror("msh");
    exit(1);
}

/* Um comando sozinho: cria o filho, troca a imagem e espera por ele. */
static void executar(char *argv[])
{
    pid_t pid = fork();

    if (pid < 0) {
        perror("msh");
        return;
    }
    if (pid == 0)
        trocar_imagem(argv);

    waitpid(pid, NULL, 0);
}

/*
 * TODO 2 - esq | dir
 *
 * esq e dir são os dois comandos, já separados e no formato de argv.
 * Para "ls -l | wc -l", esq é {"ls", "-l", NULL} e dir é {"wc", "-l", NULL}.
 *
 * Comportamento pedido: os dois comandos rodam ao mesmo tempo, o que esq
 * escreve na saída padrão chega à entrada padrão de dir, e o prompt só
 * volta depois que os dois terminaram. O msh continua vivo para o próximo
 * comando.
 *
 * Como conferir: os comandos da seção 2 do LAB06.md e o rodar.sh.
 */
static void executar_pipe(char *esq[], char *dir[])
{
    (void)esq;
    (void)dir;
    fprintf(stderr, "msh: o | ainda nao foi implementado\n");
}

int main(void)
{
    char linha[MAX_LINHA];
    char *argv[MAX_ARGS];

    while (1) {
        /* Prompt no descritor 2: o stdout do shell fica só com a saída
           dos comandos. */
        write(2, "msh> ", 5);

        /* fgets devolve NULL no fim da entrada (Ctrl-D). */
        if (fgets(linha, sizeof(linha), stdin) == NULL)
            break;

        if (parse(linha, argv) == 0)
            continue;

        if (strcmp(argv[0], "exit") == 0)
            break;

        int p = achar(argv, "|");

        if (p < 0) {
            executar(argv);
        } else if (p == 0 || argv[p + 1] == NULL) {
            fprintf(stderr, "msh: falta um comando de um dos lados do |\n");
        } else {
            argv[p] = NULL;                     /* fim do comando da esquerda */
            executar_pipe(argv, &argv[p + 1]);  /* o da direita começa depois */
        }
    }

    return 0;
}
