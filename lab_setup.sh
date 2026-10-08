#!/usr/bin/env bash
# lab_setup.sh - Preparo de sessão de laboratório, one-shot, sem tocar na imagem base.
# Sistemas Operacionais 2026.2 (Script construído com o apoio do modelo Claude Opus 5)
#
# Faz, nesta ordem:
#   0. pré-voo (ferramentas, rede, relógio, credencial residual)
#   1. compila e EXECUTA um teste com pthreads
#   2. autentica no GitHub, escolhendo sozinho o melhor caminho disponível
#   3. configura git (identidade derivada da conta, HTTPS obrigatório)
#   4. submissão de teste fim-a-fim, verificando ATRIBUIÇÃO DE AUTORIA
#
# Uso:
#   bash <(curl -sL URL-DO-SCRIPT)        # process substitution, não `curl | bash`
#   ./lab_setup.sh --logout                  # ao encerrar a sessão
#   ./lab_setup.sh --so-check                # só o diagnóstico, sem autenticar
set -uo pipefail

VERSION="1.0"
REPO_CHECKIN="${SO_SMOKE_REPO:-so-ambiente-checkin}"
API="https://api.github.com"

c_bo=$'\033[1m'; c_ok=$'\033[32m'; c_fa=$'\033[31m'; c_wa=$'\033[33m'; c_no=$'\033[0m'
[[ -t 1 ]] || { c_bo=""; c_ok=""; c_fa=""; c_wa=""; c_no=""; }

FALHAS=0; AVISOS=0
ok()    { printf '   %s %s\n' "${c_ok}ok${c_no}"     "$*"; }
aviso() { AVISOS=$((AVISOS+1)); printf '   %s %s\n' "${c_wa}!!${c_no}" "$*"; }
mau()   { FALHAS=$((FALHAS+1)); printf '   %s %s\n' "${c_fa}XX${c_no}" "$*"; }
titulo(){ printf '\n%s\n' "${c_bo}$*${c_no}"; }
morre() { printf '\n%s %s\n\n' "${c_fa}PAROU AQUI:${c_no}" "$*" >&2; exit 1; }

# Lê sempre do terminal, nunca do stdin: assim o script funciona mesmo se
# alguém o executar com `curl | bash`, caso em que o stdin está ocupado.
pergunta() { local __v="$1" __p="$2" __r; read -r -p "$__p" __r < /dev/tty; printf -v "$__v" '%s' "$__r"; }
segredo()  { local __v="$1" __p="$2" __r; read -r -s -p "$__p" __r < /dev/tty; printf '\n'; printf -v "$__v" '%s' "$__r"; }

# Extrai um campo de JSON sem depender de jq (que não está na imagem).
json_get() { # json_get <campo> <<< "$json"
  local campo="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "import sys,json
try:
    d=json.load(sys.stdin)
    v=d.get('$campo')
    print('' if v is None else v)
except Exception:
    print('')"
  else
    grep -oP "\"$campo\"\s*:\s*\"?\K[^\",}]*" | head -1
  fi
}

TOKEN=""            # nunca escrito em disco no modo PAT
MODO_AUTH=""
LOGIN=""; UID_GH=""; NOME=""

api_get() { # api_get <caminho>  -> corpo na stdout
  # O header vai num array: sem isso, "Authorization: Bearer <tok>" seria
  # quebrado em três argumentos pelo word splitting e o curl mandaria lixo.
  local -a auth=()
  [[ -n "$TOKEN" ]] && auth=(-H "Authorization: Bearer $TOKEN")
  curl -sS -m 20 -H "Accept: application/vnd.github+json" "${auth[@]}" "$API/$1" 2>/dev/null
}

# --------------------------------------------------------------------- logout
if [[ "${1:-}" == "--logout" ]]; then
  command -v gh >/dev/null 2>&1 && gh auth logout --hostname github.com 2>/dev/null
  git credential-cache exit 2>/dev/null
  rm -f  "$HOME/.git-credentials"
  rm -rf "$HOME/.config/gh"
  git config --global --unset-all user.name 2>/dev/null
  git config --global --unset-all user.email 2>/dev/null
  git config --global --unset-all credential.helper 2>/dev/null
  printf '%s\n' "${c_ok}Credenciais removidas desta máquina.${c_no}"
  exit 0
fi

# Se uma execução anterior nesta mesma sessão já baixou o gh para ~/.local/bin,
# o PATH do login não o inclui (o diretório não existia na hora do login).
# Sem isto, o script baixaria 12 MB de novo a cada execução.
[[ -d "$HOME/.local/bin" ]] && case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac

printf '%s\n' "${c_bo}so-lab v$VERSION${c_no} - Sistemas Operacionais 2026.2"
printf '%s\n' "máquina: $(hostname)   usuário: $(id -un)   $(date '+%H:%M:%S')"

# ========================================================== 0. PRÉ-VOO
titulo "[0/4] Pre-voo"

for c in git curl gcc; do
  command -v "$c" >/dev/null 2>&1 && ok "$c disponível" || mau "$c AUSENTE nesta máquina"
done
for c in make gdb valgrind python3; do
  command -v "$c" >/dev/null 2>&1 && ok "$c disponível" || aviso "$c ausente (necessário em labs futuros)"
done
[[ "$FALHAS" -eq 0 ]] || morre "faltam ferramentas básicas. Avise o professor e anote o número desta máquina."

# GH_TOKEN de ambiente teria precedência sobre qualquer login e valeria para
# quem sentasse depois nesta máquina. É credencial compartilhada disfarçada.
if [[ -n "${GH_TOKEN:-}${GITHUB_TOKEN:-}" ]]; then
  mau "há GH_TOKEN/GITHUB_TOKEN no ambiente desta máquina - AVISE O PROFESSOR"
  morre "seus commits sairiam com credencial de outra pessoa. Não prossiga."
fi

# Credencial de quem usou a máquina antes de você.
RESIDUO=0
for f in "$HOME/.git-credentials" "$HOME/.config/gh/hosts.yml"; do
  [[ -e "$f" ]] && { aviso "credencial de sessão anterior encontrada: $f"; RESIDUO=1; }
done
if [[ "$RESIDUO" -eq 1 ]]; then
  # Limpeza incondicional, sem perguntar: credencial de outra pessoa nesta
  # máquina não é uma preferência do aluno. Se ela está aqui, o home sobreviveu
  # ao logout anterior - avise o professor, porque é problema da imagem.
  "$0" --logout >/dev/null 2>&1 || true
  aviso "removida - AVISE O PROFESSOR: o home desta máquina não está sendo limpo no logout"
fi

# Keyring do GNOME. Em máquina de laboratório ele costuma estar com a senha
# antiga da imagem: qualquer aplicação que tente guardar um segredo abre um
# diálogo pedindo uma senha que ninguém sabe. O gh tenta usá-lo antes de cair
# para texto plano, e o VS Code tenta a cada inicialização.
KEYRING_ARQ="$HOME/.local/share/keyrings/login.keyring"
if [[ -e "$KEYRING_ARQ" ]]; then
  aviso "esta máquina tem keyring do GNOME - pode abrir uma janela pedindo senha"
  printf '      %s\n' "Se aparecer \"Authentication required\", clique em ${c_bo}Cancelar${c_no}."
  printf '      %s\n' "Nenhuma senha vai funcionar, e nada do laboratório depende dela."
fi
# VS Code guardando segredo em arquivo, não no keyring: sem isto o diálogo
# reaparece toda vez que o editor abre.
VSCODE_ARGV="$HOME/.config/Code/User/argv.json"
if ! grep -q '"password-store"' "$VSCODE_ARGV" 2>/dev/null; then
  mkdir -p "$(dirname "$VSCODE_ARGV")"
  [[ -f "$VSCODE_ARGV" ]] && cp -f "$VSCODE_ARGV" "$VSCODE_ARGV.bak"
  printf '{\n  "password-store": "basic"\n}\n' > "$VSCODE_ARGV"
  ok "VS Code configurado para não usar o keyring (evita o popup repetido)"
fi

# Rede. A do laboratório bloqueia a porta 22; tudo aqui é HTTPS.
CODE=$(curl -sS -o /dev/null -m 15 -w '%{http_code}' "$API" 2>/dev/null)
[[ "$CODE" == "200" ]] && ok "api.github.com responde" || mau "api.github.com não responde (HTTP ${CODE:-000})"
if timeout 25 git ls-remote --exit-code https://github.com/octocat/Hello-World.git HEAD >/dev/null 2>&1; then
  ok "git fala HTTPS com o GitHub"
else
  mau "git NÃO conversa com o GitHub por HTTPS - clone e push vão falhar"
fi

# Relógio fora de sincronia quebra TLS e o login com erro que não menciona hora.
DT=$(curl -sS -m 10 -o /dev/null -D - "$API" 2>/dev/null | tr -d '\r' \
     | awk 'tolower($1)=="date:"{ $1=""; sub(/^ /,""); print }' | tail -1)
if [[ -n "$DT" ]]; then
  R=$(date -u -d "$DT" +%s 2>/dev/null || echo "")
  if [[ -n "$R" ]]; then
    D=$(( R > $(date -u +%s) ? R - $(date -u +%s) : $(date -u +%s) - R ))
    if   [[ "$D" -gt 300 ]]; then mau   "relógio da máquina fora por ${D}s - o login vai falhar. Avise o professor."
    elif [[ "$D" -gt 60  ]]; then aviso "relógio fora por ${D}s"
    else ok "relógio sincronizado"; fi
  else
    aviso "não consegui interpretar a hora do servidor (segue assim mesmo)"
  fi
else
  aviso "não consegui ler a hora do servidor - se o login falhar, suspeite do relógio"
fi

[[ "$FALHAS" -eq 0 ]] || morre "problema de rede ou de máquina. Anote o número da máquina e avise o professor."

# ========================================================== 1. PTHREADS
titulo "[1/4] Compilando e executando um teste com threads"
TDIR=$(mktemp -d) || morre "mktemp falhou"
trap 'rm -rf "$TDIR"' EXIT
cat > "$TDIR/t.c" <<'EOF'
#include <pthread.h>
#include <stdio.h>
#define NT 4
#define NI 100000
static long c = 0;
static pthread_mutex_t m = PTHREAD_MUTEX_INITIALIZER;
static void *soma(void *a) {
    (void)a;
    for (int i = 0; i < NI; i++) { pthread_mutex_lock(&m); c++; pthread_mutex_unlock(&m); }
    return NULL;
}
int main(void) {
    pthread_t t[NT];
    for (int i = 0; i < NT; i++) if (pthread_create(&t[i], NULL, soma, NULL) != 0) return 2;
    for (int i = 0; i < NT; i++) pthread_join(t[i], NULL);
    printf("%ld\n", c);
    return 0;
}
EOF
if gcc -O2 -Wall -pthread -o "$TDIR/t" "$TDIR/t.c" 2>"$TDIR/cc.log"; then
  RES=$(timeout 30 "$TDIR/t" 2>/dev/null)
  if [[ "$RES" == "400000" ]]; then
    ok "4 threads + mutex: resultado 400000, correto"
  else
    mau "execução retornou '${RES:-vazio}', esperado 400000"
  fi
else
  mau "gcc -pthread não compila: $(head -2 "$TDIR/cc.log" | tr '\n' ' ')"
fi
[[ "$FALHAS" -eq 0 ]] || morre "esta máquina não compila o que o Projeto 1 exige. Troque de máquina e avise o professor."

if [[ "${1:-}" == "--so-check" ]]; then
  printf '\n%s\n' "${c_ok}Diagnóstico concluído: máquina apta ($AVISOS avisos).${c_no}"
  exit 0
fi

# ========================================================== 2. AUTENTICAÇÃO
titulo "[2/4] Autenticação no GitHub"

instalar_gh_local() {
  # Sem root: binário do gh em ~/.local/bin, que some no reset junto com o resto.
  local url="${SO_GH_URL:-}"
  if [[ -z "$url" ]]; then
    # Descobre a versão pelo redirect do site, NÃO pela API: a API sem
    # autenticação tem limite de 60 requisições por hora POR IP, e a turma
    # inteira sai pelo mesmo NAT do laboratório - estouraria na décima máquina.
    local ver
    ver=$(curl -sSI -m 20 https://github.com/cli/cli/releases/latest 2>/dev/null \
          | tr -d '\r' | awk 'tolower($1)=="location:"{print $2}' | sed 's#.*/tag/##' | tail -1)
    # Só se o redirect não responder: aí sim uma consulta à API (barata, uma vez).
    [[ -n "$ver" ]] || ver=$(api_get "repos/cli/cli/releases/latest" | json_get tag_name)
    [[ -n "$ver" ]] || return 1
    url="https://github.com/cli/cli/releases/download/${ver}/gh_${ver#v}_linux_amd64.tar.gz"
  fi
  mkdir -p "$HOME/.local/bin" || return 1
  curl -fsSL -m 180 "$url" -o "$TDIR/gh.tgz" 2>/dev/null || return 1
  tar xzf "$TDIR/gh.tgz" -C "$TDIR" || return 1
  local bin; bin=$(find "$TDIR" -type f -name gh -perm -u+x | head -1)
  [[ -n "$bin" ]] || return 1
  install -m 0755 "$bin" "$HOME/.local/bin/gh" || return 1
  export PATH="$HOME/.local/bin:$PATH"
  command -v gh >/dev/null 2>&1
}

login_device_flow() {
  printf '\n   %s\n' "${c_bo}Use o SEU CELULAR:${c_no}"
  printf '   %s\n'   "1. tecle Enter em tudo que o gh perguntar abaixo"
  printf '   %s\n'   "2. anote o código de 8 caracteres que ele mostrar (formato XXXX-XXXX)"
  printf '   %s\n'   "3. no CELULAR, abra  github.com/login/device , digite o código e autorize"
  printf '   %s\n'   "4. quando aparecer \"Press Enter to open ... in your browser\", tecle Enter:"
  printf '   %s\n\n' "   NADA vai abrir nesta máquina, e isso é o esperado."
  GH_BROWSER=true gh auth login --hostname github.com --git-protocol https \
      --web --scopes "repo,read:org,gist,workflow" < /dev/tty || return 1
  TOKEN=$(gh auth token --hostname github.com 2>/dev/null)
  [[ -n "$TOKEN" ]] || return 1

  # O gh grava o token em ~/.config/gh/hosts.yml, em TEXTO PLANO quando não há
  # keyring utilizável. Numa máquina cujo home sobrevive ao logout, esse arquivo
  # entrega a credencial pessoal do aluno para o próximo que sentar aqui - e
  # permite empurrar commits no nome dele, que é justamente o que não pode
  # acontecer. Então: pegamos o token e apagamos o rastro imediatamente.
  gh auth logout --hostname github.com >/dev/null 2>&1
  rm -rf "$HOME/.config/gh"
  # Daqui em diante o token vive só na memória do daemon do credential cache.
  git config --global credential.helper 'cache --timeout=21600'
  MODO_AUTH="device flow (token só em memória)"
}

login_pat() {
  printf '\n   %s\n' "${c_bo}Sem o gh nesta máquina - vamos por token.${c_no}"
  printf '   %s\n'   "No CELULAR ou em outro computador, abra este endereço"
  printf '   %s\n'   "(já vem com os escopos certos preenchidos):"
  printf '\n   %s\n\n' "${c_bo}https://github.com/settings/tokens/new?scopes=repo,workflow&description=SO-2026-2${c_no}"
  printf '   %s\n'   "Escolha validade de 90 dias, gere, e guarde o token: ele serve"
  printf '   %s\n\n' "para o semestre inteiro e você vai colá-lo a cada aula."
  segredo TOKEN "   Cole o token aqui (não aparece na tela) e tecle Enter: "
  [[ -n "$TOKEN" ]] || return 1
  # Credencial na memória de um daemon, com prazo - nunca em disco.
  git config --global credential.helper 'cache --timeout=21600'
  MODO_AUTH="token (cache em memória, 6h)"
}

if command -v gh >/dev/null 2>&1; then
  ok "gh já instalado nesta máquina"
  login_device_flow || morre "login pelo gh não concluiu"
elif sudo -n true 2>/dev/null && sudo -n apt-get install -y gh >/dev/null 2>&1; then
  ok "gh instalado via apt (sudo sem senha disponível)"
  login_device_flow || morre "login pelo gh não concluiu"
elif instalar_gh_local; then
  ok "gh baixado para ~/.local/bin (some no reset, é esperado)"
  login_device_flow || morre "login pelo gh não concluiu"
else
  aviso "não consegui obter o gh - seguindo por token"
  login_pat || morre "token não fornecido"
fi

[[ -n "$TOKEN" ]] || morre "sem credencial utilizável"

# ========================================================== 3. IDENTIDADE
titulo "[3/4] Configurando o git"

USER_JSON=$(api_get "user")
LOGIN=$(printf '%s' "$USER_JSON" | json_get login)
UID_GH=$(printf '%s' "$USER_JSON" | json_get id)
NOME=$(printf '%s' "$USER_JSON" | json_get name)
[[ -n "$LOGIN" && -n "$UID_GH" ]] || morre "o GitHub não aceitou a credencial. Token expirado ou sem escopo 'repo'?"
[[ -n "$NOME" ]] || NOME="$LOGIN"

# Identidade derivada da conta autenticada, nunca digitada: elimina commit com
# e-mail errado, nome do colega, e commit que não linka com conta nenhuma.
git config --global user.name  "$NOME"
git config --global user.email "${UID_GH}+${LOGIN}@users.noreply.github.com"
ok "conta: $LOGIN ($NOME)"
ok "e-mail dos commits: $(git config --global user.email)"

# A rede do lab bloqueia a porta 22: se você copiar a URL SSH do botão verde,
# o git a reescreve para HTTPS em vez de travar numa conexão que não completa.
git config --global --replace-all url."https://github.com/".insteadOf "git@github.com:"
git config --global --add url."https://github.com/".insteadOf "ssh://git@github.com/"
git config --global init.defaultBranch main
git config --global pull.rebase false
git config --global push.autoSetupRemote true
git config --global commit.gpgsign false
git config --global advice.detachedHead false
git config --global core.editor "${EDITOR:-nano}"
ok "HTTPS forçado, padrões aplicados"

# Vale para os dois modos: o token entra na memória do daemon do credential
# cache e não fica em disco nenhum. O daemon morre com a sessão.
printf 'protocol=https\nhost=github.com\nusername=%s\npassword=%s\n\n' "$LOGIN" "$TOKEN" \
  | git credential approve
ok "token guardado só em memória, por 6h - nada foi escrito em disco"

# ========================================================== 4. SUBMISSÃO
titulo "[4/4] Teste de submissão fim-a-fim"

CRIAR=0
api_get "repos/$LOGIN/$REPO_CHECKIN" | grep -q '"full_name"' || CRIAR=1
if [[ "$CRIAR" -eq 1 ]]; then
  curl -sS -m 30 -X POST -H "Authorization: Bearer $TOKEN" \
       -H "Accept: application/vnd.github+json" \
       -d "{\"name\":\"$REPO_CHECKIN\",\"private\":true,\"auto_init\":true,\"description\":\"Check-in de ambiente - SO 2026.2\"}" \
       "$API/user/repos" >/dev/null 2>&1
  sleep 2
  api_get "repos/$LOGIN/$REPO_CHECKIN" | grep -q '"full_name"' \
    || morre "não consegui criar o repositório $REPO_CHECKIN. O token tem escopo 'repo'?"
  ok "repositório privado $REPO_CHECKIN criado"
else
  ok "repositório $REPO_CHECKIN já existe, reaproveitando"
fi
BRANCH=$(api_get "repos/$LOGIN/$REPO_CHECKIN" | json_get default_branch); BRANCH="${BRANCH:-main}"

T0=$(date +%s)
git -C "$TDIR" clone --quiet "https://github.com/$LOGIN/$REPO_CHECKIN.git" repo 2>"$TDIR/clone.err" \
  || morre "clone falhou: $(tr '\n' ' ' < "$TDIR/clone.err")"
T1=$(date +%s)
ok "clone em $((T1-T0))s"

WD="$TDIR/repo"; mkdir -p "$WD/checkins"
STAMP=$(date -u '+%Y%m%dT%H%M%SZ'); MAQ=$(hostname)
{
  echo "check-in - Sistemas Operacionais 2026.2"
  echo "conta   : $LOGIN"
  echo "maquina : $MAQ"
  echo "data    : $STAMP"
  echo "auth    : $MODO_AUTH"
  echo "gcc     : $(gcc --version | head -1)"
  echo "pthread : 400000 (ok)"
} > "$WD/checkins/${MAQ}-${STAMP}.txt"

git -C "$WD" add checkins
git -C "$WD" commit --quiet -m "check-in: $MAQ em $STAMP" || morre "git commit falhou"
SHA=$(git -C "$WD" rev-parse HEAD)

T2=$(date +%s)
git -C "$WD" push --quiet origin "HEAD:$BRANCH" 2>"$TDIR/push.err" \
  || morre "push falhou: $(tr '\n' ' ' < "$TDIR/push.err")"
T3=$(date +%s)
ok "push em $((T3-T2))s"

REMOTO=$(git -C "$WD" ls-remote origin "refs/heads/$BRANCH" | awk '{print $1}')
[[ "$REMOTO" == "$SHA" ]] || morre "servidor em ${REMOTO:0:8}, local em ${SHA:0:8}"
ok "commit ${SHA:0:8} está no servidor"

# O teste que realmente importa: .author vem null quando o e-mail do commit não
# corresponde a nenhuma conta. O push teria dado certo e a autoria, não.
ATRIB=$(api_get "repos/$LOGIN/$REPO_CHECKIN/commits/$SHA" \
        | { command -v python3 >/dev/null 2>&1 \
            && python3 -c "import sys,json
try:
    a=json.load(sys.stdin).get('author')
    print(a.get('login') if a else '')
except Exception:
    print('')" \
            || grep -oP '\"author\":\s*\{[^}]*\"login\":\s*\"\K[^\"]+' | head -1; })
if [[ -z "$ATRIB" ]]; then
  morre "o commit subiu mas NÃO ficou atribuído a nenhuma conta do GitHub. Rode o script de novo."
elif [[ "$ATRIB" != "$LOGIN" ]]; then
  morre "commit atribuído a '$ATRIB', mas a sessão é de '$LOGIN'. Credencial cruzada - avise o professor."
fi
ok "o GitHub atribui este commit a: $ATRIB"

if [[ -n "${SO_CHECKIN_REPO:-}" && -n "${SO_CHECKIN_ISSUE:-}" ]]; then
  curl -sS -m 20 -X POST -H "Authorization: Bearer $TOKEN" \
       -H "Accept: application/vnd.github+json" \
       -d "{\"body\":\"check-in OK - \`$LOGIN\` - máquina \`$MAQ\` - $STAMP - clone $((T1-T0))s / push $((T3-T2))s - auth: $MODO_AUTH\"}" \
       "$API/repos/$SO_CHECKIN_REPO/issues/$SO_CHECKIN_ISSUE/comments" >/dev/null 2>&1 \
    && ok "check-in registrado para a turma" \
    || aviso "não consegui registrar o check-in na issue da turma (siga assim mesmo)"
fi

# ========================================================== RESUMO
printf '\n%s\n' "${c_ok}${c_bo}TUDO CERTO - VOCÊ ESTÁ SEM PENDÊNCIAS${c_no}"
printf '  conta %s, máquina %s, autenticação por %s\n' "$LOGIN" "$MAQ" "$MODO_AUTH"

# Conferência final: nenhum arquivo de credencial pode ter sobrado.
VAZOU=""
[[ -f "$HOME/.config/gh/hosts.yml" ]] && VAZOU="$VAZOU ~/.config/gh/hosts.yml"
[[ -f "$HOME/.git-credentials"     ]] && VAZOU="$VAZOU ~/.git-credentials"
if [[ -n "$VAZOU" ]]; then
  printf '\n  %s\n' "${c_wa}ATENÇÃO: sobrou credencial em disco:${VAZOU}${c_no}"
  printf '  %s\n'   "Avise o professor e rode  $0 --logout  antes de sair."
else
  ok "nenhuma credencial ficou gravada nesta máquina"
fi
[[ "$AVISOS" -gt 0 ]] && printf '  (%s avisos acima, nenhum bloqueante)\n' "$AVISOS"
cat <<FIM

  ${c_bo}ESTA MÁQUINA APAGA TUDO QUANDO VOCÊ DESLOGA.${c_no}
  O repositório remoto é o seu único armazenamento.
  Faça commit e push a cada etapa que funcionar, não no fim da aula.

  Ao sair:  $0 --logout
FIM