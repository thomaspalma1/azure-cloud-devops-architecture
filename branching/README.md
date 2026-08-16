# Branching, Estratégia de Branches

Corresponde à **Parte 4** do teste técnico.

Este documento descreve a estratégia de branches que adotei no projeto, além da forma como configurei Pull Requests, validação de build, branch policies e versionamento no Azure DevOps.

---

## Estratégia adotada

Utilizo uma estratégia baseada no GitFlow, de forma simplificada. Mantive os cinco tipos de branch citados no enunciado, porém com regras enxutas, para que o processo seja prático no dia a dia.

Optei por essa estratégia porque o projeto possui um ambiente de homologação. Sem uma branch de integração, todo merge iria direto para produção e não haveria o que promover para homologação. A branch `develop` cumpre exatamente esse papel: ela alimenta o ambiente de homologação.

Ao mesmo tempo, não adotei o GitFlow completo. A branch `release` não é obrigatória a cada entrega. Utilizo `release` apenas quando existe necessidade de estabilizar a versão antes de publicar em produção. O caminho normal do projeto é `develop` para `main`.

### Hierarquia das branches

* `main`
  * Representa o código em produção
  * Branch permanente
  * Recebe merge de `develop`, `release` e `hotfix`
  * `develop`
    * Representa o código em homologação
    * Branch permanente
    * Recebe merge de `feature`
    * `feature`
      * Criada a partir de `develop`
      * Utilizada para desenvolver novas funcionalidades
      * Removida após o merge
  * `release`
    * Criada a partir de `develop`
    * Utilizada apenas quando é necessário estabilizar a versão antes da publicação
    * Faz merge em `main` e também em `develop`
    * Removida após os merges
  * `hotfix`
    * Criada a partir de `main`
    * Utilizada para correções urgentes em produção
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

Utilizo o identificador do work item no início do nome da branch:

```
feature/ACDA-123-upload-de-arquivos
hotfix/ACDA-456-timeout-no-redis
release/1.4.0
```

Adoto esse padrão porque o Azure DevOps vincula automaticamente a branch, os commits, o Pull Request e a build ao work item correspondente. Isso me dá rastreabilidade sem esforço manual.

---

## Pull Requests

Todo merge para `main`, `develop` ou `release` acontece exclusivamente por Pull Request. O push direto está bloqueado por `branch policy`.

Configurei os Pull Requests da seguinte forma:

* **Aprovação obrigatória**
  * Exijo no mínimo duas aprovações.
  * O autor não pode aprovar o próprio Pull Request
* **Validação de build obrigatória**
  * O Pull Request só pode ser concluído se a pipeline de build e testes passar
* **Resolução de comentários**
  * Todos os comentários precisam estar resolvidos antes da conclusão
* **Vínculo com work item**
  * Exijo que o Pull Request esteja associado a um item de trabalho

Mantive a configuração igual para `main` e `develop`. Considero que código não revisado não deve entrar em `develop`, porque ele será promovido para `main` mais adiante. Aplicar o mesmo nível de proteção nas duas branches evita esse problema na origem.

---

## Validação de build

A validação de build é a `policy` que conecta a estratégia de branches às pipelines. Nenhum código entra em `main` ou `develop` sem que o build e os testes tenham passado.

### Como funciona

Quando abro um `Pull Request`, o Azure DevOps dispara automaticamente a pipeline configurada como Build Validation. O botão de conclusão do Pull Request fica bloqueado até o resultado ser aprovado.

Esse comportamento vem do gatilho declarado no topo de cada pipeline:

```yaml
pr:
  branches:
    include:
      - develop
      - main
```

### O que é executado na validação

Cada componente tem sua própria pipeline, então a validação executa apenas o build do componente alterado.

* **API em ASP.NET / C#**
  * `dotnet restore` para restaurar as dependências
  * `dotnet build` para compilar o projeto
  * `dotnet test` para executar os testes unitários

* **Worker em .NET**
  * Mesmas etapas da API, apontando para o projeto do Worker

* **Front-end em Angular**
  * `npm ci` para instalar as dependências a partir do arquivo de lock
  * `npm run build` para compilar a aplicação
  * `npm run test` para executar os testes unitários

### O que não é executado na validação

Durante um Pull Request, a pipeline não constrói imagem `Docker`, não publica no `Azure Container Registry` e não faz deploy.

Esse controle vem da condição aplicada à stage de deploy:

```yaml
condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/develop'))
```

Durante um Pull Request, a variável `Build.SourceBranch` recebe o valor `refs/pull/N/merge`, e não `refs/heads/develop`. A condição fica falsa e somente a stage de build é executada.

Adotei esse comportamento por dois motivos. Um Pull Request pode ser atualizado várias vezes durante a revisão, e publicar uma imagem a cada atualização encheria o registry de artefatos descartáveis. Além disso, o Azure Container Registry no tier Basic possui apenas 10 GiB inclusos.

---

## Branch Policies

Configuro as policies no Azure DevOps em Repos, Branches, Branch Policies.

### Policies aplicadas em `main`

* Require a minimum number of reviewers
  * Mínimo de dois revisores
  * Autor não pode aprovar o próprio Pull Request

* Check for linked work items
  * Obrigatório

* Check for comment resolution
  * Obrigatório

* Build Validation
  * Pipeline do componente, obrigatória

### Policies aplicadas em `develop`

* Require a minimum number of reviewers
  * Mínimo de dois revisores
  * Autor não pode aprovar o próprio Pull Request

* Check for linked work items
  * Obrigatório

* Check for comment resolution
  * Obrigatório

* Build Validation
  * Pipeline do componente, obrigatória

### Aprovação para publicação em produção

Além das `branch policies`, configuro uma aprovação no `Environment` de produção, em `Pipelines`, `Environments`, `Approvals and checks`.

Dessa forma separo duas decisões diferentes. A aprovação do Pull Request valida o código. A aprovação no Environment valida a publicação. O ambiente de homologação não possui aprovação, porque o deploy automático a cada merge em `develop` é justamente o objetivo desse ambiente.

---

## Versionamento

Utilizo dois tipos de numeração, porque elas respondem a perguntas diferentes.

### Versão da build

Defino o nome da build no topo de cada pipeline:

```yaml
name: $(Date:yyyyMMdd)$(Rev:.r)
```

Isso gera identificadores como `20260815.3`, que corresponde à terceira execução do dia 15 de agosto de 2026.

Esse valor alimenta a variável `$(Build.BuildNumber)`, que utilizo como:

* Tag da imagem publicada no `Azure Container Registry`
* Referência da imagem no comando de atualização do Container App

Com isso, a partir de uma revisão em execução no Container Apps eu consigo identificar a build que a gerou, o Pull Request correspondente e o work item de origem.

### Versão do produto

Para as versões do produto utilizo versionamento semântico, no formato `MAJOR.MINOR.PATCH`, aplicado como tag no Git a partir da branch `main`.

* **MAJOR**
  * Incremento quando existe mudança incompatível no contrato da API
  * Exemplo: `2.0.0`
* **MINOR**
  * Incremento quando adiciono funcionalidade compatível com a versão anterior
  * Exemplo: `1.5.0`
* **PATCH**
  * Incremento quando publico correção de defeito
  * Exemplo: `1.4.2`

```bash
git tag -a v1.4.0 -m "Release 1.4.0"
git push origin v1.4.0
```

Ou, para facilitar, também é possível criar a **tag** diretamente pela interface do `Azure DevOps`, de forma semelhante ao que pode ser feito no `GitLab`.

### Motivo de utilizar as duas numerações

A versão da build identifica qual execução da pipeline gerou determinado artefato. Ela precisa ser única e sempre crescente.

A versão do produto comunica o impacto da mudança para quem consome a aplicação. Ela precisa expressar compatibilidade.

Se eu utilizasse apenas versionamento semântico nas imagens, precisaria definir a versão manualmente a cada commit em `develop`. Se utilizasse apenas o número da build, não comunicaria nada sobre compatibilidade entre versões.

---

## Fluxo completo do processo

Este é o caminho que uma alteração percorre no projeto:

* **Desenvolvimento**
  * Crio a branch `feature` a partir de `develop`
  * Realizo os commits da funcionalidade

* **Pull Request para `develop`**
  * A validação de build é disparada automaticamente
  * A pipeline executa restore, build e testes unitários
  * Se a validação falhar, o merge fica bloqueado
  * Com a validação aprovada e a revisão concluída, realizo o merge

* **Build**
  * A pipeline compila o projeto, executa os testes e realiza a publicação

* **Deploy em homologação**
  * A pipeline constrói a imagem Docker e publica no `Azure Container Registry`
  * O comando de atualização do Container App cria uma nova revisão

* **Smoke test**
  * Para API e front-end, verifico o endpoint `/healthz`
  * Para o Worker, verifico o estado de execução da revisão, porque ele não possui ingress

* **Resultado**
  * Se o smoke test for aprovado, a nova revisão assume o tráfego
  * Se o smoke test falhar, a pipeline executa o rollback automaticamente e reativa a revisão anterior

### Ligação entre as etapas

| Etapa | Ligação com a etapa anterior |
|-------|------------------------------|
| Branch para Pull Request | A branch policy impede push direto, então o Pull Request é o único caminho |
| Pull Request para validação de build | O gatilho `pr` dispara a pipeline e o merge fica bloqueado até a aprovação |
| Validação de build para build | É a mesma stage de build, executada no contexto do Pull Request |
| Build para deploy | A stage de deploy depende da stage de build e está restrita à branch `develop` |
| Deploy para smoke test | O smoke test consulta o endereço da aplicação recém atualizada |
| Smoke test para rollback | A tarefa de rollback possui condição de execução em caso de falha |

### Sobre o rollback

Capturo o nome da revisão ativa antes de executar a atualização do Container App. Se eu consultasse essa informação apenas no momento da falha, a revisão nova já seria a mais recente e o rollback retornaria para ela mesma.

A tarefa de rollback finaliza a execução com erro, mesmo quando a reversão é concluída com sucesso. Fiz isso porque reverter não significa que o deploy funcionou. A pipeline precisa aparecer como falha para que a causa seja investigada.

---

## Fluxo de hotfix

Correções urgentes em produção não passam por `develop`. O fluxo que utilizo é:

* **Criar a branch a partir de `main`**
  * `git checkout main`
  * `git checkout -b hotfix/ACDA-456-timeout-no-redis`
  * Crio a partir de `main` porque a correção precisa partir exatamente do código que está em produção. Se eu criasse a partir de `develop`, levaria junto funcionalidades que ainda não foram homologadas.

* **Aplicar a correção e abrir Pull Request para `main`**
  * As mesmas policies continuam válidas
  * Urgência não dispensa revisão nem validação de build

* **Concluir o merge em `main`**
  * A pipeline publica a correção em produção
  * Crio a tag de versão com incremento de PATCH

* **Abrir um segundo Pull Request para `develop`**
  * Esta é a etapa mais esquecida do processo
  * Sem ela, `develop` nunca recebe a correção e o defeito volta a aparecer no próximo release

* **Remover a branch de hotfix**
  * Removo apenas após os dois merges

### Resumo do fluxo de hotfix

| Ordem | Origem | Destino | Resultado |
|-------|--------|---------|-----------|
| 1 | `main` | `hotfix` | Branch criada a partir do código em produção |
| 2 | `hotfix` | `main` | Correção publicada em produção |
| 3 | `hotfix` | `develop` | Correção preservada nos próximos releases |

---

## Observação sobre o escopo

O enunciado define como objetivo disponibilizar o ambiente de homologação. Por esse motivo, as pipelines implementam o deploy automático a partir da branch `develop`.

A estratégia de branches descrita neste documento já contempla `main` como caminho para produção, porém as stages de deploy em produção não foram implementadas, por estarem fora do escopo solicitado.