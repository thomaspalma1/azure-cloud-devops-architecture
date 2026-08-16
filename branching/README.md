# Branching, Estratégia de Branches

Corresponde à **Parte 4** do teste técnico.

Este documento descreve a **estratégia de branches** que eu adotaria no projeto, além da forma como configuraria `Pull Requests`, validação de build, `branch policies` e versionamento no `Azure DevOps`.

A estratégia apresentada aqui foi definida com base nas experiências que já adquiri profissionalmente e nas pesquisas que realizei sobre boas práticas utilizadas pela comunidade e em projetos reais. A escolha não foi feita de forma aleatória: procurei combinar o que já vi funcionar na prática com o que pesquisei, para chegar à abordagem mais adequada ao cenário proposto no teste.

## Estratégia proposta

Utilizaria uma estratégia baseada no `GitFlow`, de forma **simplificada**. Manteria os cinco tipos de branch citados no enunciado, porém com regras enxutas, para que o processo seja prático no dia a dia.

Optei por essa estratégia porque o projeto possui um **ambiente de homologação**. Sem uma branch de integração, todo merge iria direto para produção e não haveria o que promover para homologação. A branch `develop` cumpriria exatamente esse papel: seria ela quem alimentaria o ambiente de homologação.

Ao mesmo tempo, não adotaria o `GitFlow` completo. A branch `release` **não seria obrigatória** a cada entrega. Utilizaria `release` apenas quando existisse necessidade de estabilizar a versão antes de publicar em produção. O caminho normal do projeto seria `develop` para `main`.

> [!NOTE]
> O caminho padrão do projeto é `develop` → `main`. A branch `release` é **opcional** e só entra no fluxo quando a versão precisa ser estabilizada antes da publicação.

### Hierarquia das branches

* `main`
  * Representa o código em **produção**
  * Branch **permanente**
  * Recebe merge de `develop`, `release` e `hotfix`
  * `develop`
    * Representa o código em **homologação**
    * Branch **permanente**
    * Recebe merge de `feature`
    * `feature`
      * Criada a partir de `develop`
      * Utilizada para desenvolver novas funcionalidades
      * Removida após o merge
  * `release`
    * Criada a partir de `develop`
    * Utilizada apenas quando é necessário **estabilizar** a versão antes da publicação
    * Faz merge em `main` e também em `develop`
    * Removida após os merges
  * `hotfix`
    * Criada a partir de `main`
    * Utilizada para correções **urgentes** em produção
    * Faz merge em `main` e também em `develop`
    * Removida após os merges

### Relação entre branches e ambientes

| Branch | Ambiente | Publicação |
|--------|----------|------------|
| `main` | Produção | Após aprovação |
| `develop` | Homologação | Automática a cada merge |
| `feature` | Nenhum | Apenas build e testes |
| `release` | Homologação | Automática a cada merge |
| `hotfix` | Produção | Após aprovação |

### Padrão de nomes

Utilizaria o identificador da atividade no início do nome da `branch`, seguido de uma descrição curta:

```yaml
feature/4521-upload-de-arquivos
hotfix/4530-timeout-no-redis
release/1.4.0
```

O identificador viria da ferramenta de gestão utilizada pelo time. No `Azure DevOps Boards`, corresponde ao número do `work item`. Se o time utilizar `Jira` ou outra ferramenta, o identificador seguiria o formato dessa ferramenta, como `PROJ-123`.

Adotaria esse padrão porque o `Azure DevOps` vincula automaticamente a `branch`, os `commits`, o `Pull Request` e a `build` ao `work item` correspondente. Isso daria **rastreabilidade** sem esforço manual: a partir de uma revisão em execução seria possível chegar até a atividade que originou a alteração.

As branches de `release` seguiriam outro padrão, utilizando o número da versão que será publicada, porque elas não correspondem a uma atividade específica e sim a um conjunto de entregas.

## Pull Requests

Todo merge para `main`, `develop` ou `release` aconteceria exclusivamente por `Pull Request`. O push direto ficaria bloqueado por `branch policy`.

Configuraria os `Pull Requests` da seguinte forma:

* **Aprovação obrigatória**
  * Exigiria no mínimo **duas aprovações**
  * O autor não poderia aprovar o próprio `Pull Request`
* **Validação de build obrigatória**
  * O `Pull Request` só poderia ser concluído se a `pipeline` de build e testes passar
* **Resolução de comentários**
  * Todos os comentários precisariam estar **resolvidos** antes da conclusão
* **Vínculo com work item**
  * Exigiria que o `Pull Request` estivesse associado a um `work item`

Manteria a configuração igual para `main` e `develop`. Considero que código não revisado não deve entrar em `develop`, porque ele será promovido para `main` mais adiante. Aplicar o mesmo nível de proteção nas duas branches evita esse problema na origem.

## Validação de build

A validação de build é a `policy` que conecta a estratégia de branches às `pipelines`. Com ela, nenhum código entraria em `main` ou `develop` sem que o build e os testes tivessem passado.

### Como funciona

Ao abrir um `Pull Request`, o `Azure DevOps` dispara automaticamente a `pipeline` configurada como `Build Validation`. O botão de conclusão do `Pull Request` fica bloqueado até o resultado ser aprovado.

Esse comportamento vem do gatilho declarado no topo de cada `pipeline`:

```yaml
pr:
  branches:
    include:
      - develop
      - main
```

> [!IMPORTANT]
> O `Pull Request` só pode ser concluído se a `pipeline` de `Build Validation` passar. Isso garante que nenhum código quebrado chegue a `develop` ou `main`.

### O que seria executado na validação

Cada componente teria sua própria `pipeline`, então a validação executaria apenas o build do componente alterado.

* **API em ASP.NET / C#**
  * `dotnet restore` para restaurar as dependências
  * `dotnet build` para compilar o projeto
  * `dotnet test` para executar os testes unitários

* **Worker em .NET**
  * Mesmas etapas da API, apontando para o projeto do `Worker`

* **Front-end em Angular**
  * `npm ci` para instalar as dependências a partir do arquivo de lock
  * `npm run build` para compilar a aplicação
  * `npm run test` para executar os testes unitários

### O que não seria executado na validação

Durante um `Pull Request`, a `pipeline` **não** construiria imagem `Docker`, **não** publicaria no `Azure Container Registry` e **não** faria `deploy`.

Esse controle viria da condição aplicada à `stage` de `deploy`:

```yaml
condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/develop'))
```

Durante um `Pull Request`, a variável `Build.SourceBranch` recebe o valor `refs/pull/N/merge`, e não `refs/heads/develop`. A condição fica falsa e somente a `stage` de build é executada.

> [!TIP]
> Um `Pull Request` pode ser atualizado várias vezes durante a revisão, e publicar uma imagem a cada atualização encheria o `registry` de artefatos descartáveis. Além disso, o `Azure Container Registry` no tier `Basic` possui apenas **10 GiB** inclusos — mais um motivo para restringir o `deploy` à branch `develop`.

## Branch Policies

Configuraria as `policies` no `Azure DevOps` em **Repos**, **Branches**, **Branch Policies**.

### Policies aplicadas em `main`

* Require a minimum number of reviewers
  * Mínimo de **dois** revisores
  * Autor não pode aprovar o próprio `Pull Request`

* Check for linked work items
  * Obrigatório

* Check for comment resolution
  * Obrigatório

* Build Validation
  * `Pipeline` do componente, obrigatória

### Policies aplicadas em `develop`

* Require a minimum number of reviewers
  * Mínimo de **dois** revisores
  * Autor não pode aprovar o próprio `Pull Request`

* Check for linked work items
  * Obrigatório

* Check for comment resolution
  * Obrigatório

* Build Validation
  * `Pipeline` do componente, obrigatória

### Aprovação para publicação em produção

Além das `branch policies`, configuraria uma aprovação no `Environment` de produção, em **Pipelines**, **Environments**, **Approvals and checks**.

> [!IMPORTANT]
> São **duas decisões diferentes**. A aprovação do `Pull Request` valida o **código**. A aprovação no `Environment` valida a **publicação**. O ambiente de homologação não teria aprovação, porque o `deploy` automático a cada merge em `develop` é justamente o objetivo desse ambiente.

## Versionamento

Utilizaria dois tipos de numeração, porque elas respondem a perguntas diferentes.

### Versão da build

Definiria o nome da `build` no topo de cada `pipeline`:

```yaml
name: $(Date:yyyyMMdd)$(Rev:.r)
```

Isso gera identificadores como `20260815.3`, que corresponde à terceira execução do dia 15 de agosto de 2026.

Esse valor alimenta a variável `$(Build.BuildNumber)`, que utilizaria como:

* Tag da imagem publicada no `Azure Container Registry`
* Referência da imagem no comando de atualização do `Container App`

Com isso, a partir de uma revisão em execução no `Container Apps` seria possível identificar a `build` que a gerou, o `Pull Request` correspondente e o `work item` de origem.

### Versão do produto

Para as versões do produto utilizaria **versionamento semântico**, no formato `MAJOR.MINOR.PATCH`, aplicado como `tag` no `Git` a partir da branch `main`.

* **MAJOR**
  * Incremento quando existe mudança **incompatível** no contrato da API
  * Exemplo: `2.0.0`
* **MINOR**
  * Incremento quando adiciono funcionalidade **compatível** com a versão anterior
  * Exemplo: `1.5.0`
* **PATCH**
  * Incremento quando publico correção de defeito
  * Exemplo: `1.4.2`

```bash
git tag -a v1.4.0 -m "Release 1.4.0"
git push origin v1.4.0
```

> [!TIP]
> Para facilitar, também é possível criar a `tag` diretamente pela interface do `Azure DevOps`, de forma semelhante ao que pode ser feito no `GitLab`.

### Motivo de utilizar as duas numerações

A versão da `build` identifica qual execução da `pipeline` gerou determinado artefato. Ela precisa ser **única** e sempre **crescente**.

A versão do produto comunica o **impacto da mudança** para quem consome a aplicação. Ela precisa expressar compatibilidade.

Se eu utilizasse apenas versionamento semântico nas imagens, precisaria definir a versão manualmente a cada commit em `develop`. Se utilizasse apenas o número da `build`, não comunicaria nada sobre compatibilidade entre versões.

## Fluxo completo do processo

Este seria o caminho que uma alteração percorreria no projeto:

* **Desenvolvimento**
  * Criaria a branch `feature` a partir de `develop`
  * Realizaria os commits da funcionalidade

* **Pull Request para `develop`**
  * A validação de build é disparada automaticamente
  * A `pipeline` executa `restore`, `build` e testes unitários
  * Se a validação falhar, o merge fica bloqueado
  * Com a validação aprovada e a revisão concluída, o merge seria realizado

* **Build**
  * A `pipeline` compila o projeto, executa os testes e realiza a publicação

* **Deploy em homologação**
  * A `pipeline` constrói a imagem `Docker` e publica no `Azure Container Registry`
  * O comando de atualização do `Container App` cria uma nova revisão

* **Smoke test**
  * Para API e front-end, verificaria o endpoint `/healthz`
  * Para o `Worker`, verificaria o estado de execução da revisão, porque ele não possui `ingress`

* **Resultado**
  * Se o `smoke test` for aprovado, a nova revisão assume o tráfego
  * Se o `smoke test` falhar, a `pipeline` executa o `rollback` automaticamente e reativa a revisão anterior

### Ligação entre as etapas

| Etapa | Ligação com a etapa anterior |
|-------|------------------------------|
| Branch para Pull Request | A `branch policy` impede push direto, então o `Pull Request` é o único caminho |
| Pull Request para validação de build | O gatilho `pr` dispara a `pipeline` e o merge fica bloqueado até a aprovação |
| Validação de build para build | É a mesma `stage` de build, executada no contexto do `Pull Request` |
| Build para deploy | A `stage` de `deploy` depende da `stage` de build e está restrita à branch `develop` |
| Deploy para smoke test | O `smoke test` consulta o endereço da aplicação recém atualizada |
| Smoke test para rollback | A tarefa de `rollback` possui condição de execução em caso de falha |

### Sobre o rollback

> [!WARNING]
> O nome da revisão ativa é capturado **antes** da execução da atualização do `Container App`. Se essa informação fosse consultada apenas no momento da falha, a revisão nova já seria a mais recente e o `rollback` retornaria para ela mesma.

> [!IMPORTANT]
> A tarefa de `rollback` finaliza a execução com **erro**, mesmo quando a reversão é concluída com sucesso. Optei por esse comportamento porque reverter não significa que o `deploy` funcionou. A `pipeline` precisa aparecer como falha para que a causa seja investigada.

## Fluxo de hotfix

Correções urgentes em produção **não** passariam por `develop`. O fluxo seria:

* **Criar a branch a partir de `main`**
  * `git checkout main`
  * `git checkout -b hotfix/4530-timeout-no-redis`
  * Criaria a partir de `main` porque a correção precisa partir exatamente do código que está em produção. Se fosse criada a partir de `develop`, levaria junto funcionalidades que ainda não foram homologadas.

* **Aplicar a correção e abrir Pull Request para `main`**
  * As mesmas `policies` continuariam válidas
  * Urgência não dispensa revisão nem validação de build

* **Concluir o merge em `main`**
  * A `pipeline` publica a correção em produção
  * Criaria a `tag` de versão com incremento de `PATCH`

* **Abrir um segundo Pull Request para `develop`**
  * Esta é a etapa mais esquecida do processo
  * Sem ela, `develop` nunca recebe a correção e o defeito volta a aparecer no próximo `release`

* **Remover a branch de hotfix**
  * Removeria apenas após os dois merges

> [!CAUTION]
> Esquecer o `Pull Request` de `hotfix` para `develop` faz o defeito **reaparecer** no próximo `release`, porque a correção nunca chega à linha de desenvolvimento.

### Resumo do fluxo de hotfix

| Ordem | Origem | Destino | Resultado |
|-------|--------|---------|-----------|
| 1 | `main` | `hotfix` | Branch criada a partir do código em produção |
| 2 | `hotfix` | `main` | Correção publicada em produção |
| 3 | `hotfix` | `develop` | Correção preservada nos próximos releases |

## Observação sobre o escopo

O enunciado define como objetivo disponibilizar o **ambiente de homologação**. Por esse motivo, as `pipelines` implementam o `deploy` automático a partir da branch `develop`.

A estratégia de branches descrita neste documento já contempla `main` como caminho para produção, porém as `stages` de `deploy` em produção **não foram implementadas**, por estarem fora do escopo solicitado.
