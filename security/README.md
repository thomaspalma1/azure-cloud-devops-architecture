# Segurança

Corresponde à **Parte 7** do teste técnico.

Este documento descreve como eu protegeria cada camada da solução, cobrindo `secrets`, `connection strings`, `tokens`, APIs, containers, pipelines e o próprio `Azure DevOps`, utilizando `Azure Key Vault`, `Managed Identity`, `RBAC` e `Microsoft Entra ID`.

## Observação sobre esta proposta

Tenho familiaridade com os conceitos apresentados aqui, mas não me considero especialista em segurança em ambientes `Azure`. A proposta reúne o que consegui estruturar a partir do que conheço, complementado por pesquisa na documentação da Microsoft e na internet.

Mantive a abordagem deliberadamente simples. O teste apresenta um cenário hipotético e não informa o tamanho do ambiente, então evitei propor controles que fariam sentido apenas em organizações grandes ou em contextos com exigência regulatória específica.

A maior parte das decisões descritas abaixo **já está implementada** nos módulos `Terraform` e nos `Dockerfiles` deste repositório. Onde a proposta ainda não foi implementada, registro isso de forma explícita.

## Princípio que orientou as decisões

A ideia que atravessa todo este documento é simples: **o segredo mais seguro é aquele que não existe**.

Sempre que possível, eliminei a credencial em vez de protegê-la. Uma senha bem armazenada ainda pode vazar, precisa ser rotacionada e alguém precisa gerenciá-la. Quando a autenticação acontece por identidade gerenciada, **não existe senha** para nenhuma dessas coisas acontecer.

Onde não foi possível eliminar o segredo, ele fica no `Key Vault` e é lido em tempo de execução.

## Secrets

### Como eu protegeria

Armazenaria todos os segredos no `Azure Key Vault`, com as seguintes configurações:

* **Autorização por `RBAC`** em vez das `access policies` antigas
* **Acesso público desabilitado**, com conexão apenas por `private endpoint`
* **Leitura em tempo de execução** pelas aplicações, usando `Managed Identity`
* **Exclusão lógica habilitada**, permitindo recuperar um segredo removido por engano

As aplicações **não recebem os segredos** em arquivo de configuração nem em variável de ambiente com valor fixo. O `Container Apps` referencia o segredo no `Key Vault` e o resolve na inicialização do container.

### Por que essa escolha

Utilizaria `RBAC` em vez de `access policies` porque as `access policies` formam uma lista de permissões dentro do próprio recurso, **invisível para quem audita** os acessos da assinatura. Com `RBAC`, a permissão sobre o `Key Vault` aparece no mesmo lugar que todas as outras permissões do ambiente.

Desabilitar o acesso público é coerente com a existência do `private endpoint`. Manter o endereço público aberto tendo um `private endpoint` configurado seria pagar pelo controle sem obter o benefício.

### Onde já está implementado

No módulo `key-vault` do `Terraform`, com `rbac_authorization_enabled` ativado, `public_network_access_enabled` desabilitado e regra de rede que nega acesso por padrão.

## Strings de conexão

### Como eu protegeria

Este é o ponto em que apliquei o princípio de **eliminar o segredo** em vez de protegê-lo.

* **Banco de dados**
  * Configuraria o `SQL Server` para aceitar apenas autenticação via `Entra ID`, desabilitando a autenticação por usuário e senha
  * A `connection string` contém apenas o endereço do servidor e o nome do banco, **sem senha**
  * A API e o `Worker` se autenticam com suas identidades gerenciadas
* **Storage Account**
  * Desabilitaria as chaves compartilhadas da conta
  * O acesso acontece por `Entra ID`, com permissões atribuídas às identidades das aplicações
* **Redis**
  * Armazenaria o endereço de conexão no `Key Vault`
  * O acesso pela rede é restrito ao `private endpoint`

### Por que essa escolha

Com autenticação por `Entra ID` no banco e no storage, **não existe senha** para ser rotacionada, auditada ou vazada. Se alguém obtivesse a `connection string` do banco, ela sozinha **não daria acesso a nada**, porque a autenticação depende da identidade de quem faz a chamada.

Reconheço que essa abordagem exige que a aplicação utilize as bibliotecas de autenticação do `Azure`. É uma dependência a mais no código, mas considero uma troca vantajosa em relação a gerenciar senhas.

### Onde já está implementado

No módulo `sql-database`, com `azuread_authentication_only` habilitado, e no módulo `storage-account`, com `shared_access_key_enabled` desabilitado.

## Tokens

### Como eu protegeria

* **Tokens de acesso a serviços do `Azure`**
  * Não seriam armazenados. As bibliotecas do `Azure` obtêm o token automaticamente a partir da `Managed Identity` e cuidam da renovação
* **Tokens de acesso de usuários da aplicação**
  * Utilizaria o `Microsoft Entra ID` como provedor de identidade
  * A API validaria o token recebido a cada requisição
  * O front-end **nunca armazenaria** `client secret`, por ser uma aplicação pública
* **Chaves de serviços externos**
  * Ficariam no `Key Vault`, lidas em tempo de execução

### Por que essa escolha

Delegar a autenticação ao `Entra ID` evita que o time implemente e mantenha um mecanismo próprio de autenticação, que é uma área em que erros são fáceis de cometer e **difíceis de perceber**.

Sobre o front-end, é importante registrar que **qualquer valor entregue ao navegador é acessível ao usuário**. Por isso, uma aplicação `Angular` não deve conter `client secret`. Ela obtém o token do usuário e o repassa à API, que faz as chamadas autenticadas.

### Limitação que reconheço

O teste não detalha como os usuários se autenticam na aplicação. Assumi o uso do `Entra ID` por ser o provedor natural em um ambiente `Azure` e por já estar presente na solução, mas essa decisão dependeria de como o produto funciona.

## APIs

### Como eu protegeria

* **Exposição restrita**
  * A API é publicada com `ingress` interno no `Container Apps`, acessível apenas dentro do ambiente
  * Apenas o front-end tem endereço público
* **Autenticação**
  * As requisições precisam apresentar um token válido, verificado a cada chamada
* **Comunicação criptografada**
  * O tráfego externo usa `HTTPS`, com certificado gerenciado pelo `Container Apps`
* **Acesso a dados**
  * A API acessa banco, cache e storage por `private endpoint`, sem passar pela internet

### Por que essa escolha

Manter a API com `ingress` interno **reduz bastante a superfície exposta**. Mesmo que houvesse uma falha na autenticação, não seria possível alcançá-la diretamente pela internet.

O padrão é o mesmo aplicado às demais camadas: **expor apenas o que precisa ser exposto**.

### O que eu avaliaria conforme a necessidade

Se o produto passasse a expor a API para consumo externo, avaliaria o uso do `Azure API Management`, que oferece controle de limite de requisições, gestão de chaves e políticas de acesso.

Para o cenário do teste, em que apenas o front-end consome a API, considero que ele adicionaria custo e um componente a operar **sem benefício claro**.

### Onde já está implementado

No módulo `container-app`, com `external_enabled` definido como falso para a API e verdadeiro apenas para o front-end.

## Containers

### Como eu protegeria

* **Execução sem privilégios**
  * Os containers `.NET` rodam com o usuário sem privilégios definido pelas imagens oficiais
  * O container do front-end utiliza a imagem `nginx-unprivileged`, que roda com usuário não administrativo e escuta em porta não privilegiada
* **Superfície reduzida**
  * As imagens `.NET` utilizam variantes `distroless`, que **não possuem** shell, gerenciador de pacotes nem utilitários de sistema
* **Segredos fora da imagem**
  * O arquivo `.dockerignore` bloqueia arquivos de configuração local, certificados e chaves
  * Nenhum argumento de build carrega segredo
* **Versões fixadas**
  * Todas as imagens base usam versão explícita, sem utilizar a tag `latest`
* **Acesso ao registry**
  * O registry **não possui** usuário administrativo habilitado
  * As aplicações fazem download das imagens usando suas identidades gerenciadas, com permissão apenas de leitura

### Por que essa escolha

As imagens `distroless` reduzem consideravelmente a superfície de ataque. Sem shell e sem gerenciador de pacotes, alguém que conseguisse executar código dentro do container **não encontraria ferramentas para avançar**.

Sobre segredos em argumentos de build, é um ponto que considero pouco conhecido e que vale destacar: os valores de `ARG` e `ENV` **ficam registrados no histórico de camadas** da imagem e podem ser recuperados posteriormente, mesmo que uma camada seguinte os sobrescreva. Passar uma senha como `build arg` equivale a **publicá-la no registry**.

Desabilitar o usuário administrativo do registry é importante porque ele é um par de usuário e senha compartilhado, que **não pode ser atribuído a uma pessoa específica** nem rotacionado sem afetar todos que o utilizam.

### Limitação que reconheço

O registry ficou com acesso público, protegido apenas por autenticação e permissão. Isso ocorre porque o `private endpoint` no `Azure Container Registry` só está disponível no tier `Premium`, que custa cerca de **dez vezes mais** que o `Basic`.

Considero uma exceção aceitável para o cenário, já que o registry não armazena dados de negócio, mas registro que em um ambiente com exigência maior essa decisão precisaria ser revista.

### Onde já está implementado

Nos `Dockerfiles` do diretório `docker/` e no módulo `container-registry` do `Terraform`.

## Pipelines

### Como eu protegeria

* **Autenticação sem senha**
  * Utilizaria a federação de credenciais entre o `Azure DevOps` e o `Entra ID`, para que a pipeline obtenha acesso **sem uma chave armazenada**
* **Segredos em grupos de variáveis**
  * Valores sensíveis ficam marcados como secretos e **não aparecem no log** de execução
* **Permissões restritas**
  * A identidade utilizada pela pipeline recebe apenas as permissões necessárias para publicar imagens e atualizar as aplicações
* **Separação entre validar e publicar**
  * `Pull Requests` executam apenas build e testes
  * A construção e publicação de imagens acontece **somente após o merge**

### Por que essa escolha

A federação de credenciais elimina o principal problema do modelo tradicional, em que a pipeline guarda uma chave que precisa ser renovada periodicamente e que, se vazada, dá acesso ao ambiente.

A separação entre validar e publicar tem também um motivo de segurança: durante um `Pull Request`, **o código ainda não foi revisado**. Executar a etapa de publicação nesse momento significaria dar acesso ao registry a código que ninguém aprovou.

### Limitação que reconheço

A configuração da federação de credenciais é feita na interface do `Azure DevOps`, e não no `Terraform` deste repositório. Não tenho experiência prática com essa configuração específica, mas identifiquei na documentação que ela é a forma recomendada atualmente.

## Azure DevOps

### Como eu protegeria

* **Controle de acesso**
  * Os usuários acessam com suas contas do `Entra ID`
  * As permissões são atribuídas a **grupos**, não a pessoas individualmente
* **Proteção das branches**
  * Push direto bloqueado em `main` e `develop`
  * Alterações somente por `Pull Request`, com aprovação e validação de build
* **Aprovação para publicar em produção**
  * O `Environment` de produção exige aprovação manual antes do deploy
* **Rastreabilidade**
  * Cada `Pull Request` é vinculado a um `work item`, permitindo identificar o motivo de cada alteração

### Por que essa escolha

Atribuir permissões a grupos em vez de pessoas **simplifica bastante a manutenção**: quando alguém entra ou sai do time, basta ajustar o grupo, sem revisar permissões individuais espalhadas.

A aprovação no `Environment` de produção separa duas decisões diferentes. Aprovar o `Pull Request` significa concordar com o código. Aprovar a publicação significa concordar que **aquele é o momento** de colocar no ar. São decisões que nem sempre coincidem.

### Onde já está descrito

As configurações de `branch policies` e aprovação de `Environment` estão detalhadas no documento de branching.

## Managed Identity, RBAC e Entra ID

Estes três recursos aparecem em praticamente todas as seções acima, então reúno aqui como eles se relacionam.

### Microsoft Entra ID

É a **base de identidade** de todo o ambiente. Ele autentica as pessoas que acessam o `Azure DevOps` e o portal, autentica as aplicações por meio de suas identidades gerenciadas e, na proposta, também autenticaria os usuários da aplicação.

Concentrar a identidade em um único lugar traz uma vantagem prática relevante: quando alguém sai da empresa, **desativar a conta remove o acesso a tudo de uma vez**.

### Managed Identity

É o mecanismo que permite uma aplicação se autenticar **sem possuir credencial armazenada**. Cada aplicação possui sua própria identidade, o que permite atribuir permissões diferentes para cada uma e identificar nos registros de auditoria qual aplicação realizou determinada ação.

Optei por identidades atribuídas pelo usuário, criadas **antes** das aplicações. Isso permite conceder as permissões necessárias antes que a aplicação exista, evitando que o primeiro deploy falhe por não conseguir ler os segredos.

### RBAC

É o que define **o que cada identidade pode fazer**. Atribuí apenas as permissões necessárias a cada aplicação:

| Identidade | Permissões |
|---|---|
| API | Leitura de segredos, leitura de imagens, leitura e escrita em `blob` e `queue` |
| `Worker` | Leitura de segredos, leitura de imagens, leitura e escrita em `blob` e `queue` |
| Front-end | Leitura de imagens |

O front-end serve apenas arquivos estáticos, então **não precisa de acesso** a segredos, banco ou storage. Conceder permissões que ele não utiliza aumentaria o impacto de um eventual comprometimento sem trazer benefício.

### Onde já está implementado

No módulo `container-app` do `Terraform`, que cria a identidade de cada aplicação e atribui as permissões correspondentes.

## Resumo

| Item | Como é protegido | Situação |
|---|---|---|
| `Secrets` | `Key Vault` com `RBAC`, sem acesso público, lidos em tempo de execução | Implementado |
| `Connection strings` | Autenticação por `Entra ID`, sem senha no banco e no storage | Implementado |
| `Tokens` de serviço | Obtidos automaticamente pela `Managed Identity`, não armazenados | Implementado |
| `Tokens` de usuário | `Entra ID` como provedor, validados pela API | Proposta |
| APIs | `Ingress` interno, autenticação por token, acesso a dados por rede privada | Implementado |
| Containers | Usuário sem privilégios, imagens `distroless`, segredos fora da imagem | Implementado |
| Pipelines | Federação de credenciais, segredos protegidos, permissões restritas | Proposta |
| `Azure DevOps` | Acesso por `Entra ID`, branches protegidas, aprovação para produção | Proposta |

## O que eu estudaria antes de levar para produção

Registro os pontos que exigiriam mais estudo da minha parte:

* **`Microsoft Defender for Cloud`**, que oferece verificação de vulnerabilidades em imagens e recomendações de configuração. Não o incluí porque não tenho familiaridade suficiente para dimensionar seu custo e configuração, mas é o próximo recurso que eu avaliaria
* **Verificação de vulnerabilidades na pipeline**, adicionando uma etapa que analisa as imagens antes da publicação
* **Rotação de segredos**, definindo periodicidade para os segredos que não puderam ser eliminados
* **`Azure Policy`**, para impedir que recursos sejam criados fora do padrão de segurança definido

Preferi apresentar uma proposta que **consigo explicar por completo** a incluir controles que eu não saberia justificar em detalhe.