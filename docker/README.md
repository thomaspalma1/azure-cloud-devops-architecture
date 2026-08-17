# Docker - Containerização

Corresponde à **Parte 3** do teste técnico.

Esta seção cobre a organização dos Dockerfiles, o multi-stage build, a redução de tamanho das imagens, as boas práticas de segurança e o gerenciamento de variáveis de ambiente.

**Premissa assumida:** o cenário do teste é hipotético e não há código-fonte real da aplicação. O próprio enunciado pede *"Dockerfiles (exemplo)"*. Os arquivos aqui assumem uma estrutura de projeto convencional (`src/Api`, `src/Worker`, `package.json` na raiz) e são funcionais, bastaria o código real na estrutura esperada para que buildassem.

## Estrutura do diretório

![ProjectStructure](../docs/docker-structure.png)

| Componente | Arquivos | Imagem final | Ingress |
| ---------- | -------- | ------------ | ------- |
| [`api/`](./api/README.md) | `Dockerfile`, `.dockerignore` | `dotnet/aspnet:10.0-noble-chiseled` | Interno |
| [`web/`](./web/README.md) | `Dockerfile`, `.dockerignore`, `nginx.conf` | `nginx-unprivileged:1.27-alpine` | Externo |
| [`worker/`](./worker/README.md) | `Dockerfile`, `.dockerignore` | `dotnet/runtime:10.0-noble-chiseled` | Nenhum |

Cada subdiretório tem um `README.md` próprio com as decisões daquele componente.

## Organização dos Dockerfiles

**Cada Dockerfile pertence ao repositório da aplicação que ele empacota, não a um repositório central de infraestrutura.**

No cenário original há quatro repositórios no Azure DevOps (`api`, `web`, `worker`, `infrastructure`). O Dockerfile depende diretamente da estrutura interna do projeto: caminho do `.csproj`, nome do binário gerado, diretório de saída do build. Se alguém renomeia `src/Api` para `src/Api.Host`, o Dockerfile quebra.

Mantendo-o no mesmo repositório, a alteração de estrutura e a correção do Dockerfile acontecem **no mesmo Pull Request, sob a mesma revisão**. Se o Dockerfile vivesse em `infrastructure`, seriam dois Pull Requests em repositórios diferentes que precisam ser mesclados em ordem, e o build fica quebrado no intervalo.

> Neste repositório de entrega, os três Dockerfiles estão agrupados sob `docker/` apenas para facilitar a avaliação. O mesmo vale para os `.dockerignore` e o `nginx.conf`, que na prática vivem na raiz do repositório de cada aplicação.

## Gerenciamento de variáveis de ambiente

A configuração é resolvida em quatro camadas, com uma regra que atravessa todas elas: **nenhum segredo entra na imagem**.

| Camada | Definida em | Exemplos | Segredo? |
| ------ | ----------- | -------- | -------- |
| `ARG` (build) | Dockerfile, sobrescrita por `--build-arg` na pipeline | `DOTNET_VERSION`, `VERSION`, `BUILD_CONFIGURATION`, `APP_NAME`, `NODE_VERSION` | Nunca |
| `ENV` (imagem) | Dockerfile | `ASPNETCORE_HTTP_PORTS` | Nunca |
| Runtime, não sensível | Terraform, bloco `env_vars` do Container App | `ASPNETCORE_ENVIRONMENT`, `AZURE_CLIENT_ID` | Não |
| Runtime, sensível | Key Vault, referenciado como `secret` do Container App | `ConnectionStrings__SqlDatabase`, `APPLICATIONINSIGHTS_CONNECTION_STRING`, `Redis__Host` | Sim |

### Por que `ARG` e `ENV` nunca carregam segredo

Os valores de `ARG` ficam registrados no histórico da imagem e são recuperáveis com `docker history`, sem precisar executar o container. Os de `ENV` continuam definidos no processo em execução e aparecem em qualquer inspeção da imagem. Em ambos os casos, quem tiver permissão de *pull* no registry recupera o valor, e apagá-lo em uma camada posterior não resolve, porque a camada anterior permanece.

Por isso as duas camadas de build carregam apenas o que é público por natureza: versão da imagem base, configuração de compilação, nome da aplicação, porta de escuta.

### Como o segredo chega à aplicação

O segredo é gravado no Key Vault e o Container App o referencia por `key_vault_secret_id`, resolvendo-o com a **Managed Identity** atribuída ao próprio app. Ele é exposto ao processo como variável de ambiente comum, mas em nenhum momento passa pela imagem, pelo repositório ou pelos logs da pipeline.

Os nomes seguem a convenção do .NET, em que `__` representa aninhamento: `ConnectionStrings__SqlDatabase` é lido como `ConnectionStrings:SqlDatabase` pelo `IConfiguration`, sem código adicional. A implementação está em [`infrastructure/`](../infrastructure/README.md) e as decisões de identidade e RBAC em [`security/`](../security/README.md).

### A exceção do front-end

O Angular é compilado em arquivos estáticos, então não existe processo lendo variável de ambiente em runtime. A configuração do `web` é resolvida em **build time**, via `--build-arg BUILD_CONFIGURATION`. O trade-off dessa escolha está detalhado em [`web/`](./web/README.md#configuração-por-ambiente).

Isso reforça a regra anterior: como a configuração do front-end acaba embutida nos bundles servidos ao navegador, ela é pública por definição, e nenhum valor sensível pode ser colocado ali.

### As três camadas de proteção

| # | Camada | Onde |
| - | ------ | ---- |
| 1 | `.dockerignore` impede que arquivos de configuração local e chaves entrem no build context | [`api/`](./api/README.md#apidockerignore) |
| 2 | Nenhum `ARG` ou `ENV` carrega segredo | esta seção |
| 3 | Injeção em runtime a partir do Key Vault via Managed Identity | [`security/`](../security/README.md) |
