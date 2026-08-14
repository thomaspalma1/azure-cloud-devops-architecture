## `web/Dockerfile`

**Finalidade:** empacota o front-end Angular como uma imagem nginx servindo arquivos estáticos. É o único componente com **ingress externo** — o ponto de entrada da solução, acessível pela internet através do domínio customizado com TLS gerenciado.

Diferentemente da API e do Worker, o Angular não "roda" no container: ele é compilado em arquivos estáticos (HTML, JS, CSS) que o nginx serve. Isso muda toda a estrutura do Dockerfile.

### Estrutura em três estágios

| Estágio | Imagem base | Papel |
|---|---|---|
| `deps` | `node:22-alpine` | Instala as dependências npm |
| `build` | herda de `deps` | Compila a aplicação Angular |
| `final` | `nginxinc/nginx-unprivileged:1.27-alpine` | Serve os arquivos estáticos gerados |

O `node_modules` de um projeto Angular ultrapassa facilmente 500 MB, e o Node não é necessário para *servir* a aplicação — apenas para compilá-la. Descartando os dois primeiros estágios, a imagem final fica em torno de **55 MB**, a menor das três.

### Por que `npm ci` e não `npm install`

```dockerfile
RUN npm ci --no-audit --no-fund
```

`npm ci` instala exatamente o que está no `package-lock.json` e **falha** se `package.json` e o lockfile estiverem dessincronizados. `npm install` resolve a divergência silenciosamente, atualizando o lockfile — comportamento conveniente na máquina do desenvolvedor e problemático em CI, porque a build passa a produzir resultados diferentes a cada execução, sem que ninguém tenha alterado o código.

As flags `--no-audit --no-fund` suprimem a auditoria de vulnerabilidades e as mensagens de financiamento. Isso reduz o tempo de instalação; a auditoria de segurança deve acontecer como etapa própria e visível na pipeline, não como efeito colateral do install.

> A Parte 5 do enunciado pede explicitamente `npm ci` no fluxo do Angular — a escolha aqui é coerente com esse requisito.

### Por que `nginx-unprivileged` e não `nginx`

Esta é a principal decisão de segurança deste arquivo.

A imagem oficial `nginx` **exige root** para iniciar: precisa fazer bind na porta 80 (portas abaixo de 1024 são privilegiadas) e escrever em `/var/run` e `/var/cache/nginx`. Rodar um servidor web exposto à internet como root é exatamente o cenário que se busca evitar.

A alternativa comum é usar a imagem padrão e "consertar" com uma sequência de `RUN chown`, `RUN chmod`, criação de usuário e alteração de diretórios de cache. Isso funciona, mas adiciona camadas, é frágil e quebra a cada atualização da imagem base.

`nginxinc/nginx-unprivileged` é a variante oficial mantida pela própria NGINX, já configurada para rodar como **UID 101** e escutar em **8080**. Trocar a imagem base resolve o problema na origem, sem remendo.

```dockerfile
USER 101
EXPOSE 8080
```

> Note a diferença de notação em relação aos Dockerfiles .NET: lá usamos `USER $APP_UID`, uma variável definida pelas imagens da Microsoft. A imagem do nginx não expõe variável equivalente, então o UID é declarado literalmente.

### O diretório `/docker-entrypoint.d/`

```dockerfile
COPY --chown=nginx:nginx --chmod=0755 \
     docker-entrypoint.d/10-generate-env-config.sh \
     /docker-entrypoint.d/10-generate-env-config.sh
```

A imagem base do nginx executa **todos os scripts em `/docker-entrypoint.d/`** antes de iniciar o servidor, em ordem alfabética — daí o prefixo numérico `10-`. É um ponto de extensão oficial da imagem, não um hack.

Esse script resolve o problema de configuração em runtime do Angular, detalhado na seção [`docker-entrypoint.d/10-generate-env-config.sh`](#docker-entrypointd10-generate-env-configsh).

O `--chmod=0755` garante o bit de execução independentemente das permissões do arquivo no repositório (relevante quando o clone acontece no Windows, onde o bit de execução não é preservado). Essa flag depende da *parser directive* `# syntax=docker/dockerfile:1.7` na primeira linha.

### O caminho `dist/${APP_NAME}/browser`

```dockerfile
COPY --from=build --chown=nginx:nginx /src/dist/${APP_NAME}/browser /usr/share/nginx/html
```

A partir do Angular 17, o build gera a saída em `dist/<nome-da-app>/browser` — o subdiretório `browser` foi introduzido junto com o suporte a SSR, separando o bundle do cliente do bundle do servidor. Dockerfiles herdados de projetos Angular mais antigos frequentemente apontam para `dist/<app>` e falham silenciosamente, copiando a estrutura errada.

O nome da aplicação é parametrizado por `ARG APP_NAME=web` porque depende do `angular.json` do projeto real.

### Como buildar

```bash
docker build -f docker/web/Dockerfile \
  --build-arg APP_NAME=web \
  -t acracdahomolog.azurecr.io/web:1.0.0 .
```

O build context é a **raiz do repositório `web`**. Note que `nginx.conf` e `docker-entrypoint.d/` precisam estar acessíveis a partir dessa raiz — no repositório real, eles ficariam ao lado do `Dockerfile`, e não em `docker/web/` como neste repositório de entrega.

## `web/.dockerignore`

**Finalidade:** a mesma dos demais — controlar o build context. O conteúdo, porém, é **diferente** dos arquivos de API e Worker, porque a stack é outra.

### A linha mais importante

```
node_modules/
```

Em um projeto Angular, `node_modules` costuma ser o maior diretório do repositório — frequentemente centenas de MB e dezenas de milhares de arquivos. Sem esta linha, cada `docker build` empacotaria e transferiria tudo isso para o daemon antes de executar a primeira instrução.

Mas o problema vai além do tempo: **copiar `node_modules` do host quebraria a reprodutibilidade do build**. Pacotes npm podem conter binários compilados para a plataforma onde foram instalados. Um `node_modules` gerado no macOS ou Windows do desenvolvedor, copiado para dentro de um container Linux, produz falhas em tempo de execução difíceis de diagnosticar.

O `npm ci` no estágio `deps` reinstala tudo dentro do container, na plataforma correta e a partir do lockfile. O diretório local nunca deve participar disso.

### Os demais blocos

| Bloco | Motivo |
|---|---|
| `dist/`, `.angular/` | Artefatos de build local. `.angular/` é o cache de build do Angular CLI, que pode conter estado inconsistente com o código atual |
| `coverage/` | Relatórios de cobertura de teste, gerados na pipeline |
| `.env`, `.env.*` | Configuração local, frequentemente com endpoints internos ou tokens de desenvolvimento |
| `**/*.pem`, `**/*.key` | Certificados e chaves privadas — mesma proteção aplicada nos projetos .NET |
| `**/*.spec.ts` | Arquivos de teste unitário. Os testes rodam na pipeline em etapa anterior; a imagem de runtime serve apenas os arquivos compilados |
| `.DS_Store`, `**/*.swp` | Arquivos gerados por sistema operacional e editores |

### Por que a lista de segredos é mais curta que a dos projetos .NET

Os arquivos de API e Worker excluem `appsettings.Development.json`, `secrets.json` e `*.user` — convenções específicas do ecossistema .NET e do Visual Studio, que não existem em projetos Angular. Manter apenas os padrões relevantes torna o arquivo legível: uma lista com entradas que nunca farão match apenas dificulta a revisão.

> Vale reforçar o ponto que atravessa toda a Parte 3: em um front-end, o `.dockerignore` protege contra segredos entrarem na **imagem**, mas não resolve o problema mais amplo de que **qualquer valor entregue ao navegador é público**. Esse tema é tratado na seção sobre variáveis de ambiente.
