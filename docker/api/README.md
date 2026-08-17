# Docker - API

## `api/Dockerfile`

**Finalidade:** empacota a API REST em .NET 10, que é o componente central da solução, recebe as requisições do front-end, acessa SQL Database e Redis, publica mensagens na fila consumida pelo Worker e integra com o Azure OpenAI.

No ambiente provisionado, esta imagem é publicada no Azure Container Registry pela pipeline e executada como Container App com **ingress interno** (acessível apenas pelo front-end dentro do Container Apps Environment, nunca diretamente pela internet).

### Estrutura em três estágios

| Estágio   | Imagem base                         | Papel                                     |
| --------- | ----------------------------------- | ----------------------------------------- |
| `restore` | `dotnet/sdk:10.0-noble`             | Resolve as dependências NuGet             |
| `publish` | herda de `restore`                  | Compila e gera os artefatos publicados    |
| `final`   | `dotnet/aspnet:10.0-noble-chiseled` | Recebe **apenas** os artefatos compilados |

### Por que o restore é um estágio separado?

O ganho do multi-stage não está só em separar build de runtime, está em **ordenar as instruções pela frequência com que mudam**:

```dockerfile
COPY ["src/Api/Api.csproj", "src/Api/"]   # muda raramente
RUN dotnet restore ...                     # camada permanece em cache

COPY src/ src/                             # muda a cada commit
RUN dotnet publish ... --no-restore
```

Copiar apenas o `.csproj` antes do código-fonte faz com que a camada de restore permaneça em cache enquanto as dependências não mudarem. Na prática, um build de rotina pula inteiramente o download de pacotes NuGet, normalmente a maior parte do tempo de build.

Se o `COPY src/` viesse antes do restore, **qualquer** alteração de uma linha invalidaria o cache e forçaria o download completo das dependências a cada build.

> **Premissa desta etapa:** copiar um único `.csproj` assume um projeto sem dependências de projeto compartilhado e sem gerenciamento centralizado de pacotes. Se a solução real tiver um `src/Shared/Shared.csproj` referenciado pela API, ou um `Directory.Packages.props` na raiz, esses arquivos também precisam ser copiados antes do `dotnet restore`, senão o restore falha. É a primeira linha a ajustar ao plugar o código real.

### Por que a imagem final é chiseled?

`dotnet/aspnet:10.0-noble-chiseled` é uma imagem *distroless*: contém apenas o conjunto mínimo de pacotes que o .NET precisa, **sem shell, sem gerenciador de pacotes e sem utilitários de sistema**. Um atacante que consiga execução de código no container não encontra `bash`, `curl`, `apt` ou `wget` para escalar o ataque. Menos pacotes também significa menos CVEs herdadas do sistema operacional.

O SDK do .NET não é necessário para *executar* a aplicação, apenas para compilá-la. Com o multi-stage build, esse estágio é descartado e a imagem final fica na ordem de **100 MB**, contra algumas centenas de MB do SDK.

> **Consequência assumida:** sem shell no container, não é possível declarar `HEALTHCHECK` baseado em `curl` nem depurar com `docker exec`. O health check é configurado como *probe* do Container Apps, executado pela plataforma e não de dentro do container. Isso é preferível: a plataforma passa a ser a fonte de verdade sobre a saúde da réplica.

### O endpoint de health check

O `startup probe` e o `liveness probe` do Container App consultam **`GET /healthz` na porta 8080**, valor default do módulo Terraform, e o mesmo caminho é validado pelo `smoke-test.sh` após cada deploy.

Isso é um contrato entre a imagem e a infraestrutura: **a aplicação precisa expor esse endpoint**, respondendo `200` sem autenticação. Em ASP.NET Core é o `AddHealthChecks()` mapeado em `MapHealthChecks("/healthz")`. Se o caminho mudar no código, a variável `health_probe_path` do módulo precisa mudar junto, ou a réplica entra em ciclo de reinicialização, sintoma tratado no [Cenário A](../../troubleshooting/README.md) da Parte 10.

### Decisões linha a linha

| Instrução                                     | Motivo                                                                                                                                                     |
| --------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ARG DOTNET_VERSION=10.0`                     | Versão parametrizada no topo, atualizar a versão do .NET é mudar uma linha, não caçar ocorrências pelo arquivo                                             |
| `ARG BUILD_CONFIGURATION=Release`             | Configuração de compilação do .NET, com `Release` como default. É o mesmo parâmetro que o Dockerfile gerado pelo Visual Studio expõe, e deixa um build de investigação (`--build-arg BUILD_CONFIGURATION=Debug`) acessível sem editar o arquivo |
| `--runtime linux-x64` no restore e no publish | Restaura e publica para um runtime específico, permitindo `--no-restore` no publish sem refazer o trabalho                                                 |
| `--self-contained false`                      | A imagem base já contém o runtime .NET; empacotá-lo novamente duplicaria dezenas de MB                                                                     |
| `-p:PublishReadyToRun=true`                   | Pré-compila IL para código nativo. **Aumenta** a imagem em alguns MB, mas reduz o tempo de startup, ver justificativa abaixo                               |
| `-p:Version=${VERSION}`                       | Versão do assembly recebida da pipeline por `--build-arg`, ver [Rastreabilidade](#rastreabilidade-da-versão)                                               |
| `ENV ASPNETCORE_HTTP_PORTS=8080`              | Porta não privilegiada (>1024): processos não-root não podem fazer bind abaixo de 1024                                                                     |
| `ENV DOTNET_RUNNING_IN_CONTAINER=true`        | Sinaliza ao runtime que ele está em container, ajustando heurísticas de GC e telemetria. As imagens oficiais já definem esta variável; mantida explícita para que o comportamento não dependa da imagem base |
| `ENV DOTNET_EnableDiagnostics=0`              | Desliga o diagnostic server (usado por `dotnet-trace`/`dotnet-dump`), que é superfície de ataque desnecessária fora de desenvolvimento                     |
| `COPY --chown=$APP_UID:$APP_UID`              | Arquivos já entram com o dono correto, evitando um `RUN chown` que criaria uma camada adicional duplicando o conteúdo                                      |
| `USER $APP_UID`                               | Executa como usuário sem privilégios. `$APP_UID` é definido pelas imagens base oficiais do .NET; usar a variável em vez do número literal mantém o arquivo correto se o UID mudar em uma versão futura |
| `ENTRYPOINT ["dotnet", "Api.dll"]`            | Forma *exec* (não *shell*): o processo roda como PID 1 e recebe `SIGTERM` diretamente, permitindo shutdown gracioso quando o Container Apps reduz réplicas |

### Sobre `PublishReadyToRun` e o scale-to-zero

Esta flag aumenta a imagem em alguns MB em troca de um startup mais rápido, uma escolha que só faz sentido à luz do dimensionamento definido em [`sizing/`](../../sizing/README.md#observação-sobre-o-scale-to-zero).

Como os Container Apps operam com **scale-to-zero** em homologação (`min_replicas = 0`), toda requisição após um período de ociosidade dispara um *cold start*. Trocar alguns MB de imagem por menos tempo de inicialização é vantajoso nesse cenário. Em um serviço com réplica sempre ativa (`min_replicas = 1`), o cálculo poderia ser diferente.

### Rastreabilidade da versão

A pipeline passa a versão do assembly no build da imagem:

```yaml
arguments: --build-arg VERSION=1.0.0-$(Build.BuildNumber)
```

`1.0.0` é a versão base do produto e `$(Build.BuildNumber)` (por exemplo, `api-20260817.1`) entra como sufixo de pré-lançamento. O formato é válido para o `-p:Version` do MSBuild, e o resultado é que a versão reportada pelo assembly em execução identifica a execução exata da pipeline que o gerou.

A tag da imagem usa o mesmo `$(Build.BuildNumber)`, então imagem e assembly apontam para o mesmo build.

### Como buildar

```bash
docker build -f docker/api/Dockerfile \
  --build-arg VERSION=1.0.0 \
  -t acracdahomolog.azurecr.io/api:1.0.0 .
```

O build context é a **raiz do repositório `api`**, não o diretório `docker/api/`, por isso o `.` no final e o `-f` apontando para o caminho do Dockerfile. Os caminhos dentro do arquivo (`src/Api/...`) são relativos a essa raiz.

Na pipeline, esse build é executado pela task `Docker@2` em modo `buildAndPush`, que também publica no Azure Container Registry, ver [`pipelines/`](../../pipelines/README.md).

## `api/.dockerignore`

**Finalidade:** define o que **não** é enviado ao daemon do Docker quando o build começa. Atende diretamente a dois dos quatro itens que o enunciado pede para demonstrar: *redução de tamanho das imagens* e *boas práticas de segurança*.

### Como funciona o build context

Ao executar `docker build ... .`, o Docker empacota **todo o conteúdo do diretório indicado** (o `.`) e envia para o daemon antes de processar qualquer instrução do Dockerfile. Sem `.dockerignore`, isso inclui `bin/`, `obj/`, o histórico completo do `.git` e qualquer arquivo de configuração local, mesmo que o Dockerfile nunca use nada disso.

| Problema                 | Consequência                                                                                           |
| ------------------------ | ------------------------------------------------------------------------------------------------------ |
| Contexto grande          | Cada build gasta tempo empacotando e transferindo arquivos desnecessários                              |
| Invalidação de cache     | Um `COPY` copia arquivos irrelevantes; alterar qualquer um deles invalida a camada e força rebuild     |
| **Vazamento de segredo** | Um `appsettings.Development.json` com senha entra na imagem e vai parar no registry                    |

### O bloco mais importante

```
**/appsettings.Development.json
**/appsettings.Local.json
**/*.user
**/secrets.json
**/.env
**/.env.*
**/*.pfx
**/*.key
**/*.pem
```

Esta é a primeira barreira contra credenciais entrando na imagem. O risco é real e silencioso: `appsettings.Development.json` costuma conter connection strings com senha para o banco local, e nada no processo de build avisa que ele foi copiado. Uma vez dentro de uma camada da imagem, o valor é recuperável por qualquer pessoa com acesso de pull ao registry, inclusive se uma camada posterior "apagar" o arquivo, já que a camada anterior continua no histórico.

Os padrões `*.pfx`, `*.key` e `*.pem` cobrem certificados e chaves privadas, que ocasionalmente ficam no diretório do projeto durante desenvolvimento local.

> Esta é a **primeira** de três camadas de proteção contra vazamento de segredo. As outras duas estão descritas em [Gerenciamento de variáveis de ambiente](../README.md#gerenciamento-de-variáveis-de-ambiente).

### Os demais blocos

| Bloco                                          | Motivo                                                                                                                                                                                                      |
| ---------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `**/bin/`, `**/obj/`, `**/out/`, `**/publish/` | Artefatos de build da máquina local. Além de inúteis, podem **conflitar** com o build dentro do container, um `obj/` gerado com outro RID ou versão de SDK causa erros de restore difíceis de diagnosticar   |
| `.git/`                                        | O histórico completo do repositório frequentemente é a maior pasta do projeto, e nada do build depende dele                                                                                                 |
| `azure-pipelines*.yaml`, `.github/`            | Definições de CI não fazem parte da aplicação                                                                                                                                                               |
| `.vs/`, `.vscode/`, `.idea/`                   | Configuração de IDE, específica de cada desenvolvedor                                                                                                                                                       |
| `**/Dockerfile*`, `**/docker-compose*.yml`     | O Dockerfile é lido pelo `-f`, não precisa estar dentro do contexto                                                                                                                                         |
| `**/*.md`, `docs/`                             | Documentação não entra em imagem de runtime                                                                                                                                                                 |
| `**/*Tests/`, `**/*.Tests/`                    | Projetos de teste são compilados e executados na pipeline, em etapa anterior ao build da imagem. A imagem de runtime não deve conter código de teste                                                        |

O padrão `**/` faz o match em qualquer nível de diretório. Escrever `bin/` sozinho excluiria apenas um `bin` na raiz do contexto; `**/bin/` cobre `src/Api/bin`, `src/Shared/bin` e assim por diante, necessário em soluções .NET com múltiplos projetos.

### Relação com o Dockerfile

O `.dockerignore` é o que torna seguro usar `COPY src/ src/` no estágio de publish. Sem ele, essa instrução arrastaria `bin/`, `obj/` e arquivos de configuração local junto com o código-fonte.

Vale notar que o `.dockerignore` **precisa estar na raiz do build context**, não ao lado do Dockerfile. Como o build é executado a partir da raiz do repositório `api`, este arquivo vive lá; aqui em `docker/api/` ele está apenas agrupado para facilitar a avaliação.
