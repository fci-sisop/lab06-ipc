#!/usr/bin/env bash
# rodar.sh - executa os exercicios do Lab 6 e grava o resumo em resultados.txt.
#
# Uso: bash rodar.sh
#
# A parte de cada exercicio so roda depois que a previsao dele (1.1, 2.1 e
# 3.1) estiver escrita no LAB06.md. O arquivo resultados.txt entra no commit:
# rode este script de novo antes da entrega final.

SAIDA=resultados.txt
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

if ! make >/dev/null 2>"$TMP/make.err"; then
    echo "A compilacao falhou:"
    cat "$TMP/make.err"
    exit 1
fi

: > "$SAIDA"

# ------------------------------------------------------------------ apoio

diz() { printf '%s\n' "$*" | tee -a "$SAIDA"; }

# previsao_escrita 1.1 -> verdadeiro se a linha '>' da pergunta tem resposta
previsao_escrita() {
    awk -v q="$1" '
        index($0, "**" q " ") == 1    { achou = 1; next }
        achou && /^(\*\*[0-9]|## )/   { exit }
        achou && /^>/ {
            sub(/^>[ \t]*/, "")
            if (length($0) > 2) ok = 1
        }
        END { exit ok ? 0 : 1 }
    ' LAB06.md
}

# vivo PID -> verdadeiro se o processo existe e nao e um zumbi
vivo() {
    local st
    st=$(awk '{ sub(/^.*\) /, ""); print $1 }' "/proc/$1/stat" 2>/dev/null)
    [ -n "$st" ] && [ "$st" != "Z" ]
}

# espera_fim PID SEGUNDOS -> verdadeiro se o processo terminou dentro do prazo
espera_fim() {
    local i
    for ((i = 0; i < $2 * 10; i++)); do
        vivo "$1" || return 0
        sleep 0.1
    done
    return 1
}

nome() { cat "/proc/$1/comm" 2>/dev/null || echo "?"; }

# filhos PID -> pids dos filhos diretos
filhos() {
    awk -v p="$1" '$1 == "PPid:" && $2 == p { split(FILENAME, a, "/"); print a[3] }' \
        /proc/[0-9]*/status 2>/dev/null
}

# do_grupo PGID -> nomes dos processos vivos do grupo
do_grupo() {
    awk -v g="$1" '{
        n = $0; sub(/^[0-9]+ \(/, "", n); sub(/\).*$/, "", n)
        r = $0; sub(/^.*\) /, "", r); split(r, c, " ")
        if (c[3] == g && c[1] != "Z") print n
    }' /proc/[0-9]*/stat 2>/dev/null
}

mata() { { kill -KILL "$@"; wait "$@"; } 2>/dev/null; }

# pontas PID [PIPE_A_IGNORAR] -> pontas de pipe abertas no processo
pontas() {
    local pid=$1 ignorar=${2:-} f alvo n modo lista=""
    for f in "/proc/$pid/fd"/*; do
        alvo=$(readlink "$f" 2>/dev/null) || continue
        case $alvo in pipe:*) ;; *) continue ;; esac
        [ "$alvo" = "$ignorar" ] && continue
        n=${f##*/}
        modo=$(awk '/^flags:/ { print substr($2, length($2)) }' "/proc/$pid/fdinfo/$n" 2>/dev/null)
        case $modo in
            0) modo=leitura ;;
            1) modo=escrita ;;
            *) modo="leitura e escrita" ;;
        esac
        lista="$lista${lista:+, }fd $n $modo"
    done
    echo "${lista:-nenhuma}"
}

# disposicao PID -> o que o processo faz ao receber SIGINT
disposicao() {
    local ign cgt
    ign=$(awk '/^SigIgn:/ { print $2 }' "/proc/$1/status" 2>/dev/null)
    cgt=$(awk '/^SigCgt:/ { print $2 }' "/proc/$1/status" 2>/dev/null)
    if [ -z "$ign" ]; then
        echo "?"
    elif (( 16#${ign: -1} & 2 )); then
        echo "ignorado"
    elif (( 16#${cgt: -1} & 2 )); then
        echo "tratado por uma funcao do programa"
    else
        echo "padrao (encerra o processo)"
    fi
}

estado() { if vivo "$1"; then echo "vivo"; else echo "morreu"; fi; }

# ------------------------------------------------------------ exercicio 1

parte1() {
    local pai filho

    diz "== Exercicio 1: ex1 =="
    ./ex1 >/dev/null 2>"$TMP/ex1.err" &
    pai=$!
    sleep 1.5
    filho=$(filhos "$pai" | head -n 1)

    diz "Pontas do pipe abertas com 1,5 s de execucao:"
    diz "  pai   (pid $pai): $(pontas "$pai")"
    [ -n "$filho" ] && diz "  filho (pid $filho): $(pontas "$filho")"

    if ! espera_fim "$pai" 5; then
        diz "Passados 6,5 s o programa continuava rodando; o script encerrou os processos."
    elif [ -n "$filho" ] && vivo "$filho"; then
        diz "O pai terminou, mas o filho (pid $filho) continuava rodando; o script o encerrou."
    else
        diz "O programa terminou sozinho."
    fi
    mata "$pai" $filho
    diz "Ultima mensagem do programa: $(tail -n 1 "$TMP/ex1.err")"
}

# ------------------------------------------------------------ exercicio 2

testa() {
    local cmd=$1 t saida sobras
    printf '%s\nexit\n' "$cmd" | timeout 7 ./msh >"$TMP/out" 2>/dev/null &
    t=$!
    if espera_fim "$t" 5; then
        saida=$(tr '\n' ' ' <"$TMP/out" | sed 's/ *$//' | cut -c1-40)
        diz "  $(printf '%-26s' "$cmd") terminou; saida: ${saida:-(vazia)}"
        sobras=$(do_grupo "$t" | sort -u | tr '\n' ' ')
        [ -n "$sobras" ] && diz "  $(printf '%-26s' '') ficou rodando depois do exit: $sobras"
    else
        sobras=$(do_grupo "$t" | grep -v '^timeout$' | sort -u | tr '\n' ' ')
        diz "  $(printf '%-26s' "$cmd") NAO TERMINOU em 5 s; ainda rodando: ${sobras:-?}"
    fi
    { kill -KILL -- "-$t"; wait "$t"; } 2>/dev/null
}

parte2() {
    local msh entrada f n=0

    diz "== Exercicio 2: | no msh =="
    ( printf 'sleep 3 | sleep 3\n'; sleep 4; printf 'exit\n' ) 2>/dev/null |
        ./msh >/dev/null 2>&1 &
    msh=$!
    sleep 1

    diz "Pontas do pipe abertas com 'sleep 3 | sleep 3' rodando dentro do msh:"
    if vivo "$msh"; then
        entrada=$(readlink "/proc/$msh/fd/0" 2>/dev/null)
        diz "  pid $msh ($(nome "$msh")): $(pontas "$msh" "$entrada")"
        for f in $(filhos "$msh"); do
            diz "    filho, pid $f ($(nome "$f")): $(pontas "$f" "$entrada")"
            n=$((n + 1))
        done
        [ "$n" -eq 0 ] && diz "    (nenhum processo filho neste momento)"
    else
        diz "  (o processo do msh nao estava mais rodando)"
    fi
    espera_fim "$msh" 6
    mata "$msh"

    diz "Comandos de teste:"
    testa 'ls | wc -l'
    testa 'cat msh.c | grep -c TODO'
    testa 'yes | head -3'
}

# ------------------------------------------------------------ exercicio 3

# O Ctrl-C do terminal envia SIGINT ao grupo de processos em primeiro plano.
# O script reproduz isso com kill no grupo; antes, confere se consegue.
sinal_chega() {
    local p
    set -m
    sleep 30 &
    p=$!
    set +m
    sleep 0.3
    kill -INT -- "-$p" 2>/dev/null
    sleep 0.5
    if vivo "$p"; then
        { kill -KILL -- "-$p"; wait "$p"; } 2>/dev/null
        return 1
    fi
    wait "$p" 2>/dev/null
    return 0
}

parte3() {
    local msh filho

    diz "== Exercicio 3: Ctrl-C no msh =="
    if ! sinal_chega; then
        diz "Este ambiente nao deixou o script enviar SIGINT a um grupo. Teste o Ctrl-C a mao."
        return
    fi

    mkfifo "$TMP/entrada"
    set -m
    ./msh <"$TMP/entrada" >"$TMP/out3" 2>/dev/null &
    msh=$!
    set +m
    exec 3>"$TMP/entrada"
    printf 'sleep 30\n' >&3
    sleep 1
    filho=$(filhos "$msh" | head -n 1)

    diz "Disposicao do SIGINT com 'sleep 30' rodando dentro do msh:"
    diz "  pid $msh ($(nome "$msh")): $(disposicao "$msh")"
    if [ -n "$filho" ]; then
        diz "  pid $filho ($(nome "$filho")): $(disposicao "$filho")"
    fi

    kill -INT -- "-$msh" 2>/dev/null
    sleep 1
    diz "Um segundo depois de um SIGINT enviado aos dois processos:"
    diz "  msh:   $(estado "$msh")"
    [ -n "$filho" ] && diz "  sleep: $(estado "$filho")"

    if vivo "$msh"; then
        ( printf 'echo ainda vivo\nexit\n' >&3 ) 2>/dev/null
    fi
    exec 3>&-
    espera_fim "$msh" 2
    if grep -q 'ainda vivo' "$TMP/out3" 2>/dev/null; then
        diz "  o msh executou o comando seguinte (echo ainda vivo)"
    fi
    { kill -KILL -- "-$msh"; wait "$msh"; } 2>/dev/null
}

# ---------------------------------------------------------------- roteiro

diz "Lab 6 - resultados gerados em $(date '+%d/%m/%Y %H:%M:%S')"
diz ""

for parte in 1 2 3; do
    if previsao_escrita "$parte.1"; then
        "parte$parte"
    else
        diz "== Exercicio $parte =="
        diz "Nao executado: escreva antes a previsao $parte.1 no LAB06.md,"
        diz "na linha que comeca com '>' logo abaixo da pergunta."
    fi
    diz ""
done
