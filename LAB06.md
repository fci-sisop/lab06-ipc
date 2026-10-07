RA:

Nome:

Turma:

# Lab 6 - Comunicação entre processos: pipes e sinais

Sistemas Operacionais - FCI Mackenzie - 2026.2

Neste lab o `msh` do Lab 3 ganha o `|` e passa a sobreviver ao Ctrl-C. São
três exercícios: os dois primeiros são feitos em sala e o terceiro é a
conclusão, feita depois da aula.

Cada exercício segue a mesma ordem: uma leitura curta, uma previsão escrita
antes de rodar, um TODO e uma pergunta para depois. As respostas vão neste
arquivo, na linha que começa com `>` logo abaixo de cada pergunta. Duas ou
três frases bastam.

```
make             # compila ex1 e msh
bash rodar.sh    # executa, mede e grava o resumo em resultados.txt
bash check.sh    # mostra o que já está feito e o que falta
```

O `rodar.sh` só executa a parte de um exercício depois que a previsão dele
estiver escrita aqui.

---

## 1. Um pipe entre pai e filho

Arquivo: `ex1_pipe.c`

**Leitura (5 minutos).** `man 7 pipe`, seção "I/O on pipes and FIFOs":
https://man7.org/linux/man-pages/man7/pipe.7.html

Se preferir um tutorial com código: Beej's Guide to IPC, capítulo "Pipes",
seção "fork() and pipe()": https://beej.us/guide/bgipc/html/split/pipes.html

**1.1 Antes de rodar.** Leia o `ex1_pipe.c` inteiro. O pai manda três linhas,
fecha a ponta de escrita e espera o filho. Qual vai ser a última mensagem na
tela, e o programa termina sozinho? Escreva a previsão e o raciocínio que
levou a ela. Conferir primeiro e escrever depois não vale.

> 

Agora rode `./ex1` e depois `bash rodar.sh`. O script mostra quais pontas do
pipe cada processo tinha abertas no meio da execução.

**TODO 1.** Faça o filho perceber que a entrada acabou, para que o programa
encerre sozinho com a mensagem `pai: o filho terminou`. O laço de leitura do
filho e o `wait` do pai ficam como estão.

**1.2 Depois da correção.** Rode o `rodar.sh` de novo e compare a tabela de
pontas abertas com a que saiu antes da sua correção. O que mudou, e por que
essa mudança faz o `read` do filho devolver 0?

> 

---

## 2. O | no msh

Arquivo: `msh.c`

O arquivo traz o `msh` do Lab 3 funcionando, já com o `>`. A linha digitada
chega separada no `|`, e falta a função `executar_pipe()`.

**Leitura (10 minutos).** Beej's Guide to IPC, capítulo "Pipes", seção "The
search for Pipe as we know it": https://beej.us/guide/bgipc/html/split/pipes.html

Se preferir o livro da disciplina: OSTEP, capítulo 5, seção 5.4, do exemplo
de redirecionamento até o parágrafo sobre pipes:
https://pages.cs.wisc.edu/~remzi/OSTEP/cpu-api.pdf

**2.1 Antes de implementar.** Pense no `ls | wc -l` rodando dentro do msh.
Contando o próprio msh, quantos processos existem nesse momento? Para cada
um, diga quais pontas do pipe ele precisa manter abertas para o comando
funcionar e terminar.

> 

**TODO 2.** Implemente `executar_pipe()`. O comportamento pedido está no
comentário da função. Confira com:

```
msh> ls | wc -l
msh> cat msh.c | grep -c TODO
msh> yes | head -3
msh> echo o msh continua vivo
```

Os três primeiros devolvem o prompt sozinhos, e o quarto mostra que o shell
segue de pé. Depois rode `bash rodar.sh` e compare a tabela do exercício 2
com a sua previsão.

**2.2 Depois de funcionar.** O `yes` escreve `y` sem parar e não tem condição
de parada. No `yes | head -3` ele terminou mesmo assim. O que o encerrou?

> 

Para quem terminar cedo (não vale nota): `cat msh.c | grep TODO | wc -l`,
com dois pipes na mesma linha.

---

## 3. Conclusão: Ctrl-C no msh

Arquivo: `msh.c`

**Leitura (10 minutos).** `man 7 signal`, seção "Signal dispositions", e a
linha do SIGINT na tabela "Standard signals":
https://man7.org/linux/man-pages/man7/signal.7.html

Se preferir um tutorial com código: Beej's Guide to IPC, capítulo "Signals",
até o fim da seção "Catching Signals for Fun and Profit!":
https://beej.us/guide/bgipc/html/split/signals.html

**3.1 Antes de mexer no código.** No msh como está, você vai rodar `sleep 30`
e apertar Ctrl-C. Quem morre: só o `sleep`, só o msh, ou os dois? Escreva a
previsão e o motivo, e só então teste.

> 

**TODO 3.** Faça o Ctrl-C encerrar o comando que está rodando e deixar o msh
vivo, pronto para o próximo comando. No prompt vazio o Ctrl-C também não
pode encerrar o msh (para sair continuam valendo `exit` e Ctrl-D). Confira:

```
msh> sleep 30                (Ctrl-C: o prompt volta na hora)
msh> sleep 30 | sleep 30     (Ctrl-C: o prompt volta na hora)
msh>                         (Ctrl-C: o msh não fecha)
msh> echo ainda vivo
```

**3.2 Depois de funcionar.** O `rodar.sh` mostra a disposição do SIGINT no msh
e no `sleep`. Os dois recebem o mesmo sinal e reagem de formas diferentes.
Explique por quê, e diga em que ponto do seu código a disposição do `sleep`
ficou diferente da do msh.

> 

---

## Entrega

**Em sala (checkpoint):** exercícios 1 e 2 e o RA na primeira linha deste
arquivo, com `git push` até o fim da aula. O `check.sh` mostra a linha
"Checkpoint da aula: completo" quando estiver tudo certo.

**Conclusão:** exercício 3, as seis respostas, `USO_DE_IA.md` marcado e
`resultados.txt` gerado depois da última mudança no código. O prazo é o da
tarefa no Moodle.

```
bash rodar.sh
bash check.sh
git add .
git commit -m "lab06"
git push
```
