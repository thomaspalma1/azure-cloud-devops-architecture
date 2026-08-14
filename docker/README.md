# Docker - Containerização

Corresponde à **Parte 3** do teste técnico.

Esta seção atende ao seguinte requisito do enunciado:

> **Explique:** Como organizaria os Dockerfiles da solução.
> **Mostre:**
>
> * multi-stage build;
> * redução de tamanho das imagens;
> * boas práticas de segurança;
> * gerenciamento de variáveis de ambiente.

**Premissa assumida:** o cenário do teste é hipotético e não há código-fonte real da aplicação. O próprio enunciado pede *"Dockerfiles (exemplo)"*. Os arquivos aqui assumem uma estrutura de projeto convencional (`src/Api`, `src/Worker`, `package.json` na raiz) e são funcionais, bastaria o código real na estrutura esperada para que buildassem. Todos passam sem avisos no [hadolint](https://github.com/hadolint/hadolint).

## Organização dos Dockerfiles

**Cada Dockerfile pertence ao repositório da aplicação que ele empacota, não a um repositório central de infraestrutura.**

No cenário original há quatro repositórios no Azure DevOps (`api`, `web`, `worker`, `infrastructure`). O Dockerfile depende diretamente da estrutura interna do projeto: caminho do `.csproj`, nome do assembly, diretório de saída do build. Se alguém renomeia `src/Api` para `src/Api.Host`, o Dockerfile quebra.

Mantendo-o no mesmo repositório, a alteração de estrutura e a correção do Dockerfile acontecem **no mesmo Pull Request, sob a mesma revisão**. Se o Dockerfile vivesse em `infrastructure`, seriam dois Pull Requests em repositórios diferentes que precisam ser mesclados em ordem, e o build fica quebrada no intervalo.

> Neste repositório de entrega, os três Dockerfiles estão agrupados sob `docker/` apenas para facilitar a avaliação.

### Estrutura do diretório

![ProjectStructure](../docs/docker-structure.png)
