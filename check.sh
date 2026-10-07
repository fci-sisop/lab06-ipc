#!/usr/bin/env bash
# check.sh - verificacao local do Lab 6.
#
# Uso: bash check.sh
#
# Roda so na sua maquina e nao envia nada. Pode rodar quantas vezes quiser.

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

falta_aula=0
falta_final=0

# marca <aula|final> <ok|falta> <texto>
marca() {
    if [ "$2" = "ok" ]; then
        echo "  [ok]    $3"
    else
        echo "  [falta] $3"
        if [ "$1" = "aula" ]; then falta_aula=$((falta_aula + 1)); fi
        falta_final=$((falta_final + 1))
    fi
}

vivo() {
    local st
    st=$(awk '{ sub(/^.*\) /, ""); print $1 }' "/proc/$1/stat" 2>/dev/null)
    [ -n "$st" ] && [ "$st" != "Z" ]
}

espera_fim() {
    local i
    for ((i = 0; i < $2 * 10; i++)); do
        vivo "$1" || return 0
        sleep 0.1
    done
    return 1
}

agora_ms() { echo $(( $(date +%s%N) / 1000000 )); }

# msh_roda <limite em s> <texto de entrada>: saida do msh em $TMP/out.
# Devolve 124 se o msh nao terminou dentro do limite.
msh_roda() {
    local t rc
    printf '%s' "$2" | timeout "$1" ./msh >"$TMP/out" 2>/dev/null &
    t=$!
    wait "$t"
    rc=$?
    kill -KILL -- "-$t" 2>/dev/null
    return "$rc"
}

# ------------------------------------------------------------- compilacao

echo "== Compilacao =="
make clean >/dev/null 2>&1
if make all >"$TMP/build.log" 2>&1; then
    marca aula ok "ex1 e msh compilam"
else
    marca aula falta "a compilacao falhou (rode 'make' para ver o erro)"
fi

# ----------------------------------------------------- exercicios em sala

echo
echo "== Exercicio 1 =="
if [ -x ./ex1 ]; then
    timeout 8 ./ex1 >/dev/null 2>"$TMP/ex1.err" &
    t=$!
    wait "$t"
    rc=$?
    kill -KILL -- "-$t" 2>/dev/null
    if [ "$rc" -eq 0 ] && grep -q "a entrada acabou" "$TMP/ex1.err" &&
       grep -q "o filho terminou" "$TMP/ex1.err"; then
        marca aula ok "ex1 termina sozinho, com o filho vendo o fim da entrada"
    else
        marca aula falta "ex1 nao termina sozinho, ou o filho nao viu o fim da entrada"
    fi
else
    marca aula falta "ex1 nao compilou"
fi

echo
echo "== Exercicio 2 =="
if [ -x ./msh ]; then
    msh_roda 5 $'echo abc | tr a-c A-C\necho depois\nexit\n'
    rc=$?
    if [ "$rc" -ne 124 ] && grep -qx "ABC" "$TMP/out"; then
        marca aula ok "a saida do comando da esquerda chega ao da direita"
    else
        marca aula falta "'echo abc | tr a-c A-C' deveria imprimir ABC e devolver o prompt"
    fi
    if [ "$rc" -ne 124 ] && grep -qx "ABC" "$TMP/out" && grep -qx "depois" "$TMP/out"; then
        marca aula ok "o msh continua vivo depois de um comando com |"
    else
        marca aula falta "depois de um comando com |, o msh deveria executar o comando seguinte"
    fi

    msh_roda 5 $'yes | head -3\nexit\n'
    if [ "$?" -ne 124 ] && [ "$(grep -cx "y" "$TMP/out")" -eq 3 ]; then
        marca aula ok "'yes | head -3' imprime tres linhas e devolve o prompt"
    else
        marca aula falta "'yes | head -3' deveria imprimir tres linhas e devolver o prompt"
    fi

    t0=$(agora_ms)
    msh_roda 8 $'sleep 2 | true\necho depois\nexit\n'
    rc=$?
    t1=$(agora_ms)
    if [ "$rc" -ne 124 ] && grep -qx "depois" "$TMP/out" && [ $((t1 - t0)) -ge 1900 ]; then
        marca aula ok "o prompt espera os dois lados do | terminarem"
    else
        marca aula falta "em 'sleep 2 | true' o prompt so deveria voltar depois dos 2 s"
    fi
else
    marca aula falta "msh nao compilou"
fi

echo
echo "== Identificacao =="
if head -n 1 LAB06.md 2>/dev/null | tr -d '\r' | grep -Eq '^RA:[[:space:]]*[0-9]{8}[[:space:]]*$'; then
    marca aula ok "RA na primeira linha do LAB06.md"
else
    marca aula falta "a primeira linha do LAB06.md deve ser 'RA: ' seguido do seu RA (8 digitos)"
fi

# ------------------------------------------------------------- conclusao

# Envia SIGINT ao grupo do msh, como o Ctrl-C do terminal, e confere se o
# msh ainda executa um comando depois. $1 = comando em execucao na hora do
# sinal (vazio para o prompt parado). Devolve 0 se tudo certo, 1 se o msh
# nao sobreviveu, 2 se o comando em execucao nao foi encerrado.
teste_ctrl_c() {
    local msh filho rc=0
    rm -f "$TMP/fifo"
    mkfifo "$TMP/fifo"
    set -m
    ./msh <"$TMP/fifo" >"$TMP/out" 2>/dev/null &
    msh=$!
    set +m
    exec 3>"$TMP/fifo"
    [ -n "$1" ] && printf '%s\n' "$1" >&3
    sleep 0.7
    filho=$(awk -v p="$msh" '$1 == "PPid:" && $2 == p { split(FILENAME, a, "/"); print a[3] }' \
            /proc/[0-9]*/status 2>/dev/null | head -n 1)
    kill -INT -- "-$msh" 2>/dev/null
    sleep 0.7
    if [ -n "$filho" ] && vivo "$filho"; then
        rc=2
    else
        if vivo "$msh"; then
            ( printf 'echo sobrevivi\nexit\n' >&3 ) 2>/dev/null
        fi
        exec 3>&-
        espera_fim "$msh" 2
        grep -qx "sobrevivi" "$TMP/out" 2>/dev/null || rc=1
    fi
    exec 3>&-
    { kill -KILL -- "-$msh"; wait "$msh"; } 2>/dev/null
    return "$rc"
}

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

echo
echo "== Exercicio 3 (conclusao) =="
if [ ! -x ./msh ]; then
    marca final falta "msh nao compilou"
elif ! sinal_chega; then
    echo "  [--]    este ambiente nao deixa o script enviar SIGINT; teste o Ctrl-C a mao"
else
    teste_ctrl_c "sleep 30"
    case $? in
        0) marca final ok "Ctrl-C encerra o comando em execucao e o msh continua vivo" ;;
        2) marca final falta "o comando em execucao deveria ser encerrado pelo Ctrl-C" ;;
        *) marca final falta "o msh deveria sobreviver ao Ctrl-C dado durante um comando" ;;
    esac
    teste_ctrl_c ""
    if [ "$?" -eq 0 ]; then
        marca final ok "Ctrl-C no prompt vazio nao encerra o msh"
    else
        marca final falta "o msh deveria sobreviver ao Ctrl-C no prompt vazio"
    fi
fi

# ------------------------------------------------------------ entregaveis

echo
echo "== Entregaveis =="
respondidas=$(grep -cE '^>[[:space:]]*[^[:space:]].{2,}' LAB06.md 2>/dev/null)
respondidas=${respondidas:-0}
if [ "$respondidas" -ge 6 ]; then
    marca final ok "as 6 perguntas do LAB06.md tem resposta"
else
    marca final falta "LAB06.md com $respondidas de 6 respostas (a resposta vai na linha que comeca com '>')"
fi

if grep -Eq '^- \[ *[xX] *\]' USO_DE_IA.md 2>/dev/null; then
    marca final ok "USO_DE_IA.md com pelo menos uma opcao marcada"
else
    marca final falta "USO_DE_IA.md sem nenhuma opcao marcada (entregar assim desconta 25% do lab)"
fi

if [ ! -s resultados.txt ] || ! grep -q "Disposicao do SIGINT" resultados.txt; then
    marca final falta "resultados.txt sem as tres partes (rode 'bash rodar.sh' com as previsoes escritas)"
elif [ resultados.txt -ot msh.c ] || [ resultados.txt -ot ex1_pipe.c ]; then
    marca final falta "resultados.txt e mais antigo que o codigo (rode 'bash rodar.sh' de novo)"
else
    marca final ok "resultados.txt gerado depois da ultima mudanca no codigo"
fi

# ----------------------------------------------------------------- resumo

echo
echo "-----------------------------------------------------------"
if [ "$falta_aula" -eq 0 ]; then
    echo "Checkpoint da aula (exercicios 1 e 2 e RA): completo"
else
    echo "Checkpoint da aula (exercicios 1 e 2 e RA): faltam $falta_aula item(ns)"
fi
if [ "$falta_final" -eq 0 ]; then
    echo "Entrega final: completa"
else
    echo "Entrega final: faltam $falta_final item(ns)"
fi
[ "$falta_final" -eq 0 ]
