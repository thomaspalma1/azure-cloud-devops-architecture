# Docker - Front-end

## `web/Dockerfile`

**Finalidade:** empacota o front-end Angular como uma imagem nginx servindo arquivos estáticos. É o único componente com **ingress externo**, o ponto de entrada da solução, acessível pela internet através do domínio customizado com TLS gerenciado.

Diferentemente da API e do Worker, o Angular não "roda" no container: ele é compilado em arquivos estáticos (HTML, JS, CSS) que o nginx serve. Isso muda toda a estrutura do Dockerfile.

### Estrutura em três estágios

| Estágio | Imagem base | Papel |
|---|---|---|
| `deps` | `node:22-alpine` | Instala as dependências npm |
| `build` | herda de `deps` | Compila a aplicação Angular |
| `final` | `nginxinc/nginx-unprivileged:1.27-alpine` | Serve os arquivos estáticos gerados |

O `node_modules` de um projeto Angular passa facilmente de centenas de MB, e o Node não é necessário para *servir* a aplicação, apenas para compilá-la. Descartando os dois primeiros estágios, a imagem final fica na ordem de **50 MB**, a menor das três.

### Por que `npm ci` e não `npm install`

```dockerfile
RUN npm ci --no-audit --no-fund
```

`npm ci` instala exatamente o que está no `package-lock.json` e **falha** se `package.json` e o lockfile estiverem dessincronizados. `npm install` resolve a divergência silenciosamente, atualizando o lockfile, comportamento conveniente na máquina do desenvolvedor e problemático em CI, porque o build passa a produzir resultados diferentes a cada execução sem que ninguém tenha alterado o código.

As flags `--no-audit --no-fund` suprimem a auditoria de vulnerabilidades e as mensagens de financiamento. Isso reduz o tempo de instalação; a auditoria de segurança deve acontecer como etapa própria e visível na pipeline, não como efeito colateral do install.

> A Parte 5 do enunciado pede explicitamente `npm ci` no fluxo do Angular, a escolha aqui é coerente com esse requisito.

### Configuração por ambiente

```dockerfile
ARG BUILD_CONFIGURATION=production
RUN npm run build -- --configuration=${BUILD_CONFIGURATION}
```

A configuração do front-end é resolvida em **build time**, usando o mecanismo nativo do Angular: cada `configuration` declarada no `angular.json` aponta para um arquivo `environment.*.ts` com os valores daquele ambiente (endpoint da API, connection string do Application Insights, flags de recurso).

A pipeline passa o valor correspondente ao ambiente de destino:

```bash
docker build --build-arg BUILD_CONFIGURATION=homolog ...
```

> **Trade-off assumido:** resolver a configuração em build time significa que **cada ambiente gera uma imagem distinta**, a imagem validada em homologação não é o mesmo artefato binário promovido para produção. Para um ambiente de homologação essa é uma troca aceitável, e mantém a solução simples e legível.
>
> Em um cenário onde a paridade de artefato entre ambientes seja requisito rígido, a alternativa seria injetar a configuração em runtime, por exemplo gerando um `assets/env.js` no entrypoint do container a partir de variáveis de ambiente, permitindo que a mesma imagem rode em qualquer ambiente. O custo seria um script a mais para manter.
>
> Note que essa questão **não existe no backend**: API e Worker leem configuração em runtime a partir de variáveis de ambiente injetadas pelo Container Apps. A restrição é específica de aplicações front-end compiladas, e o quadro completo está em [Gerenciamento de variáveis de ambiente](../README.md#gerenciamento-de-variáveis-de-ambiente).

Como o resultado do build é servido ao navegador, **nada do que entra aqui é secreto**: qualquer valor embutido nos bundles é legível por quem abrir a aplicação.

A consequência prática aparece no Terraform: o Container App do `web` é o único dos três que **não recebe `env_vars` nem `secrets`**. Não haveria a quem entregá-las, porque dentro do container só existe o nginx servindo arquivos, e a configuração da aplicação já foi resolvida no build. Isso inclui a connection string do Application Insights, que é compilada no bundle e usada pelo navegador, não lida por um processo no container.

### Por que `nginx-unprivileged` e não `nginx`

Esta é a principal decisão de segurança deste arquivo.

A imagem oficial `nginx` **exige root** para iniciar: precisa fazer bind na porta 80 (portas abaixo de 1024 são privilegiadas) e escrever em `/var/run` e `/var/cache/nginx`. Rodar um servidor web exposto à internet como root é exatamente o cenário que se busca evitar.

A alternativa comum é usar a imagem padrão e "consertar" com uma sequência de `RUN chown`, `RUN chmod`, criação de usuário e alteração de diretórios de cache. Isso funciona, mas adiciona camadas e vira manutenção a cada atualização da imagem base.

`nginxinc/nginx-unprivileged` é a variante oficial mantida pela própria NGINX, já configurada para rodar como **UID 101** e escutar em **8080**. Trocar a imagem base resolve o problema na origem, sem remendo.

```dockerfile
USER 101
EXPOSE 8080
```

Ambas as instruções repetem o que a imagem base já faz. São mantidas explícitas para que a garantia de execução sem privilégios esteja declarada no próprio arquivo, e não dependa de um default da imagem base.

> Note a diferença de notação em relação aos Dockerfiles .NET: lá usamos `USER $APP_UID`, uma variável definida pelas imagens da Microsoft. A imagem do nginx não expõe variável equivalente, então o UID é declarado literalmente.

### O caminho `dist/${APP_NAME}/browser`

```dockerfile
COPY --from=build --chown=nginx:nginx /src/dist/${APP_NAME}/browser /usr/share/nginx/html
```

A partir do Angular 17, o build gera a saída em `dist/<nome-da-app>/browser`, o subdiretório `browser` foi introduzido junto com o suporte a SSR, separando o bundle do cliente do bundle do servidor. Dockerfiles herdados de projetos Angular mais antigos frequentemente apontam para `dist/<app>` e falham, copiando a estrutura errada.

O nome da aplicação é parametrizado por `ARG APP_NAME=web` porque depende do `angular.json` do projeto real.

### Como buildar

```bash
docker build -f docker/web/Dockerfile \
  --build-arg APP_NAME=web \
  --build-arg BUILD_CONFIGURATION=homolog \
  -t acracdahomolog.azurecr.io/web:1.0.0 .
```

O build context é a **raiz do repositório `web`**.

> **Atenção ao layout deste repositório:** a instrução `COPY nginx.conf ...` procura o arquivo na raiz do build context. No repositório real da aplicação, `Dockerfile` e `nginx.conf` ficam lado a lado na raiz e o build funciona direto. Aqui em `docker/web/` eles estão agrupados para facilitar a avaliação, então este comando, executado a partir da raiz deste repositório de entrega, não encontraria o `nginx.conf`. É consequência do agrupamento, não do Dockerfile.

---

## `web/.dockerignore`

Mesma finalidade do [`.dockerignore` da API](../api/README.md#apidockerignore): manter fora do build context o que não é necessário para compilar. O conteúdo é diferente porque a stack é diferente.

| Bloco | Motivo |
|---|---|
| `node_modules/` | O item mais importante da lista. Além do tamanho, copiá-lo da máquina do desenvolvedor **quebraria o build**: pacotes com binários nativos são compilados para o sistema operacional do host e não rodariam na imagem Alpine. O `npm ci` do estágio `deps` precisa instalar do zero |
| `dist/`, `.angular/`, `coverage/` | Saída de build, cache do compilador Angular e relatório de cobertura, todos gerados localmente e sem uso dentro do container |
| `.env`, `.env.*`, `**/*.pem`, `**/*.key` | Mesma barreira contra segredo entrando na imagem, adaptada ao que aparece em um projeto front-end |
| `**/*.spec.ts` | Testes rodam na pipeline, em etapa anterior ao build da imagem |

### Quando o padrão usa `**/`

O `.dockerignore` da API prefixa quase tudo com `**/` porque uma solução .NET tem vários projetos, cada um com seu próprio `bin/` e `obj/` em subdiretórios.

Aqui a regra é outra, e depende do que está sendo excluído:

| Tipo | Padrão | Motivo |
|---|---|---|
| Diretórios da raiz | `node_modules/`, `dist/`, `.angular/`, `coverage/`, `.vscode/` | Existem em um lugar só, na raiz do projeto Angular, então o prefixo não acrescentaria nada |
| Padrões por extensão | `**/*.pem`, `**/*.key`, `**/*.md`, `**/*.spec.ts`, `**/*.swp` | Podem aparecer em qualquer subpasta de `src/`, então precisam casar em qualquer nível |

A diferença em relação ao `.dockerignore` da API é deliberada: cada arquivo descreve a estrutura do repositório em que vive, em vez de replicar um padrão único nos três componentes.

---

## `web/nginx.conf`

**Finalidade:** configuração do servidor que entrega a aplicação Angular. Substitui o `default.conf` da imagem base e resolve quatro problemas distintos: roteamento de SPA, cabeçalhos de segurança, política de cache e health check.

É montado em `/etc/nginx/conf.d/default.conf` pelo Dockerfile, não em `/etc/nginx/nginx.conf`. A imagem base já traz o `nginx.conf` principal configurado para rodar sem privilégios (worker processes, PID file, diretórios de cache em caminhos graváveis pelo UID 101); sobrescrevê-lo quebraria justamente o que a variante *unprivileged* resolve. O arquivo aqui define apenas o bloco `server`.

### `listen 8080`

Coerente com a imagem `nginx-unprivileged` e com o `EXPOSE 8080` do Dockerfile. Um processo não-root não consegue fazer bind em portas abaixo de 1024, o que descarta a porta 80.

Esse valor também precisa coincidir com o `targetPort` do ingress configurado no Container App, divergência aqui produz um container que sobe normalmente mas nunca recebe tráfego, sintoma tratado no [Cenário A](../../troubleshooting/README.md) da Parte 10.

### SPA fallback

```nginx
location / {
    expires -1;
    try_files $uri $uri/ /index.html;
}
```

Este é o bloco que faz uma Single Page Application funcionar em um servidor de arquivos estáticos.

O roteamento de uma aplicação Angular acontece no navegador: `/pedidos/123` não corresponde a nenhum arquivo em disco. Se o usuário acessa essa URL diretamente, ou simplesmente atualiza a página estando nela, o nginx procuraria por um arquivo `pedidos/123` e retornaria **404**.

`try_files $uri $uri/ /index.html` instrui o nginx a tentar o arquivo, depois o diretório, e por fim entregar o `index.html`, a partir do qual o roteador do Angular assume e renderiza a rota correta.

### Estratégia de cache

A configuração aplica políticas deliberadamente diferentes por tipo de arquivo:

| Recurso | Diretiva | Cabeçalho resultante |
|---|---|---|
| Bundles gerados pelo build (`.js`, `.css`, fontes) | `expires 1y` | `Cache-Control: max-age=31536000` |
| `index.html` e demais arquivos (via `location /`) | `expires -1` | `Cache-Control: no-cache` |

Os bundles têm o hash do conteúdo no nome: se o conteúdo muda, o nome muda. Cachear por um ano é seguro e elimina requisições a cada visita.

O `index.html` é o oposto: referencia os bundles do deploy atual e nunca pode ficar defasado. `no-cache` não impede o navegador de guardá-lo, apenas obriga a revalidar antes de usar — o servidor responde `304` quando nada mudou, ou entrega a versão nova após um deploy. É isso que permite publicar sem invalidar cache manualmente.

O cache longo cobre apenas o que o build do Angular versiona por hash. Os arquivos de `src/assets/` são copiados mantendo o nome original, então um `assets/logo.png` cacheado por um ano nunca seria atualizado. Por isso imagens e ícones caem no `location /`.

### Endpoint `/healthz`

```nginx
location = /healthz {
    access_log   off;
    default_type text/plain;
    return 200 'healthy';
}
```

Este endpoint existe por causa de uma decisão tomada nos outros Dockerfiles: **as imagens são distroless e não possuem shell**, o que inviabiliza um `HEALTHCHECK` interno baseado em `curl` ou `wget`. A verificação passa a ser responsabilidade da plataforma, e este é o caminho consultado pelos probes do Container Apps e pelo `smoke-test.sh` da pipeline.

| Probe | Função |
|---|---|
| *Startup* | Determina quando a réplica terminou de inicializar e pode receber tráfego |
| *Liveness* | Detecta réplica travada e dispara reinicialização |

`access_log off` evita poluir os logs, o probe é executado a cada poucos segundos e registrá-lo geraria volume de ingestão no Log Analytics sem valor diagnóstico, com custo real (ver [`sizing/`](../../sizing/README.md)).

O `return 200` responde diretamente, sem tocar o disco. Um health check que dependesse de ler um arquivo poderia falhar por motivos não relacionados à saúde da aplicação.

### Cabeçalhos de segurança

| Cabeçalho | Proteção |
|---|---|
| `X-Content-Type-Options: nosniff` | Impede o navegador de inferir o tipo de conteúdo, bloqueando ataques em que um arquivo enviado por upload é interpretado como script |
| `X-Frame-Options: DENY` | Impede que a aplicação seja carregada em `<iframe>`, bloqueando *clickjacking* |
| `Referrer-Policy: no-referrer` | Evita que URLs internas (potencialmente com identificadores) vazem para sites externos pelo header `Referer` |
| `Permissions-Policy` | Desabilita explicitamente acesso a geolocalização, microfone e câmera |

O parâmetro `always` garante que os cabeçalhos sejam enviados também em respostas de erro (4xx, 5xx). Sem ele, o nginx os omite nessas respostas, que são páginas servidas ao navegador como qualquer outra.

Os quatro são declarados **uma única vez**, no nível `server`, e valem para todas as rotas.

> **Cuidado ao editar:** isso só funciona porque nenhum `location` declara `add_header` próprio. O nginx não mescla essa diretiva — um bloco filho com `add_header` substitui integralmente a lista herdada, e os cabeçalhos de segurança sumiriam daquela rota. É por isso que o cache usa `expires` e o `/healthz` usa `default_type`, em vez de `add_header`. O `nginx -t` continuaria passando; o problema só apareceria ao inspecionar uma resposta real.

`server_tokens off` remove a versão do nginx do header `Server` e das páginas de erro.

> **O que não está aqui:** `Content-Security-Policy` e `Strict-Transport-Security`. A CSP depende do que a aplicação real carrega (CDNs, fontes externas, scripts inline do Angular) e uma política genérica quebraria a aplicação ou seria permissiva demais para ter valor. Já o HSTS não faz sentido neste arquivo porque o TLS termina no ingress do Container Apps: o nginx aqui recebe a requisição já sem TLS, então esse cabeçalho pertence à camada do ingress, e é um dos pontos que eu verificaria antes de expor o ambiente.

### Compressão

```nginx
gzip            on;
gzip_vary       on;
gzip_min_length 1024;
gzip_proxied    any;
gzip_types      text/css text/javascript application/javascript application/json image/svg+xml;
```

Bundles JavaScript de aplicações Angular são grandes e comprimem bem. `gzip_min_length 1024` evita comprimir arquivos pequenos, onde o custo de CPU supera a economia de banda.

`gzip_vary on` adiciona o header `Vary: Accept-Encoding`, necessário para que caches intermediários armazenem separadamente as versões comprimida e não comprimida.

`gzip_proxied any` existe por causa do ingress do Container Apps: o nginx nunca recebe a requisição diretamente do navegador, e por padrão o nginx **não** comprime respostas de requisições que chegam marcadas como proxied.

A lista de tipos **não inclui imagens rasterizadas** (`png`, `jpg`, `gif`): esses formatos já são comprimidos, e reprocessá-los apenas consome CPU. O `image/svg+xml` está na lista porque SVG é XML, texto, e comprime bem.

### Como validar

A sintaxe pode ser verificada sem buildar a imagem completa:

```bash
docker run --rm \
  -v "$PWD/docker/web/nginx.conf:/etc/nginx/conf.d/default.conf:ro" \
  nginxinc/nginx-unprivileged:1.27-alpine nginx -t
```

Saída esperada:

```
nginx: configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
```

O `nginx -t` valida apenas a sintaxe. Como os cabeçalhos dependem de regras de herança, vale conferir uma resposta real subindo o container com os arquivos do build e inspecionando as rotas:

```bash
curl -I http://localhost:8080/index.html   # espera Cache-Control: no-cache
curl -I http://localhost:8080/main.<hash>.js   # espera Cache-Control: max-age=31536000
curl -I http://localhost:8080/rota-inexistente  # espera 200 (fallback da SPA)
```

Os quatro cabeçalhos de segurança devem aparecer nas três respostas, e também em um `404`, por causa do `always`.
