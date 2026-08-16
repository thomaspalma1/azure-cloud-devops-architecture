# Dimensionamento

Corresponde à **Parte 2** do teste técnico.

Este documento apresenta as `SKUs` (sigla em inglês para *Stock Keeping Unit*, o termo que a `Azure` usa para identificar a variante ou o tier de cada recurso) que eu escolheria para cada recurso, a justificativa técnica de cada escolha, uma estimativa de **custo mensal** e quais recursos poderiam **crescer automaticamente** conforme a demanda.

## Sobre as estimativas

O cenário do teste é **hipotético** e não informa volume de usuários, número de requisições ou volume de dados. Sem esses dados, qualquer cálculo detalhado seria uma suposição apresentada como certeza.

Por isso, adotei a seguinte abordagem: escolher as `SKUs` de entrada de cada serviço, justificar tecnicamente por que elas atenderiam o cenário e apresentar valores aproximados como **ordem de grandeza**.

Os valores abaixo vêm das páginas oficiais de preço da `Azure`, considerando preços de lista da região `East US`. A região `Brazil South` costuma praticar valores superiores, tipicamente entre **20% e 40%** acima. Para um orçamento real, os números precisariam ser confirmados na calculadora de preços da `Azure` com a região definitiva.

Em um projeto real, eu trataria esse dimensionamento como ponto de partida e o revisaria com base no consumo observado pelo `Azure Cost Management`.

### Premissas que assumi

| Premissa | Valor assumido |
|----------|----------------|
| Perfil de uso | Ambiente interno, utilizado pela equipe de desenvolvimento e testes |
| Janela de uso | Aproximadamente **6 horas por dia**, em dias úteis |
| Fora da janela | Aplicações com **zero réplicas** ativas |
| Volume de dados no banco | Abaixo de **50 GB** |
| Volume de arquivos enviados | Abaixo de **50 GB** |
| Ingestão de logs | Aproximadamente **8 GB por mês** |

## SKUs escolhidas e custo estimado

| Recurso | SKU escolhida | Custo mensal aproximado | Cresce automaticamente |
|---------|---------------|-------------------------|------------------------|
| `Container Apps` (três aplicações) | `Consumption` | 8 dólares | Sim |
| `Container Apps Environment` | `Consumption` | Sem custo próprio | Não se aplica |
| `Azure Container Registry` | `Basic` | 5 dólares | Apenas o armazenamento |
| `Azure SQL Database` | `Standard S1` | 29 dólares | Não |
| `Azure Managed Redis` | `Balanced B0`, sem alta disponibilidade | 13 dólares | Não |
| `Storage Account` | `Standard LRS`, camada `Hot` | 2 dólares | Sim |
| `Key Vault` | `Standard` | 1 dólar | Sim |
| `Log Analytics Workspace` | `Pay as you go`, retenção de 30 dias | 7 dólares | Sim |
| `Application Insights` | Integrado ao workspace | Incluído acima | Sim |
| `Azure Monitor` e alertas | Métricas de plataforma | 1 dólar | Não se aplica |
| `Virtual Network` | Padrão | Sem custo | Não se aplica |
| `Private Endpoints` (quatro recursos) | Padrão | 29 dólares | Não se aplica |
| `Azure DNS` | Zona pública | 1 dólar | Não se aplica |
| `Azure OpenAI` | Cobrança por token | Entre 10 e 30 dólares | Sim |

**Total aproximado em East US:** entre **106 e 126 dólares** por mês.

**Total aproximado em Brazil South** (considerando um acréscimo de 30%): entre **138 e 164 dólares** por mês.

## Justificativa das escolhas

### Container Apps

Utilizaria o plano `Consumption`, em que a cobrança é feita por segundo de execução. A principal vantagem no cenário é permitir que as aplicações fiquem com **zero réplicas** quando não há uso.

Como o ambiente é de homologação e ficaria ocioso fora do horário de trabalho, isso elimina o custo de processamento durante boa parte do mês. O plano `Dedicated` faria sentido apenas com carga constante, o que não é o caso.

Distribuiria os recursos assim:

* **Front-end** `Angular`: 0,25 de CPU e 0,5 GB de memória, por servir apenas arquivos estáticos
* **API** em `.NET`: 0,5 de CPU e 1 GB de memória
* **Worker** em `.NET`: 0,5 de CPU e 1 GB de memória

### Azure Container Registry

Escolheria o tier `Basic`, que inclui **10 GB** de armazenamento. Como são apenas três imagens com poucas publicações diárias, esse espaço seria suficiente.

Os tiers `Standard` e `Premium` se justificam quando há necessidade de maior capacidade de download simultâneo, o que não se aplica a um ambiente de homologação.

Uma limitação dessa escolha: `private endpoint` só está disponível no tier `Premium`, cerca de **dez vezes mais caro** que o `Basic`. Por isso, o registry ficaria com acesso público, protegido por `Managed Identity` e `RBAC`. Como ele não armazena dados de negócio, considero uma **exceção aceitável**.

### Azure SQL Database

Escolheria a SKU `Standard S1`, que corresponde a **20 DTU** e já inclui **250 GB** de armazenamento.

A SKU `S0`, com **10 DTU**, atenderia um uso muito leve, mas o `S1` oferece alguma margem para testes de carga sem sofrer limitação imediata. Como é um ambiente de homologação, é esperado que ele receba testes que simulem cenários de uso mais intenso.

O modelo `DTU` também traz previsibilidade de custo, o que facilita a estimativa quando ainda não se conhece o padrão de consumo real.

### Azure Managed Redis

Escolheria a SKU `Balanced B0`, que corresponde a **1 GB**, sem alta disponibilidade.

A opção sem alta disponibilidade reduz o custo pela **metade** e é indicada pela própria Microsoft para ambientes de desenvolvimento e testes. Em um ambiente de homologação, a perda temporária do cache não causa impacto relevante, já que os dados podem ser recarregados a partir do banco.

O enunciado cita "Azure Redis Cache". Optei pelo `Azure Managed Redis` porque os tiers `Basic`, `Standard` e `Premium` do `Azure Cache for Redis` têm descontinuação anunciada para **30 de setembro de 2028**, e a orientação da Microsoft é utilizar o `Azure Managed Redis` para cargas novas. Provisionar hoje um serviço com fim de vida anunciado criaria uma migração conhecida logo no início do projeto.

### Storage Account

Escolheria `Standard` com replicação `LRS`, que mantém três cópias dos dados dentro da mesma região.

A replicação `GRS`, que replica para uma segunda região, praticamente **dobra o custo**. Para um ambiente de homologação, onde os dados podem ser recriados, esse investimento não se justifica.

### Key Vault

Escolheria o tier `Standard`. O tier `Premium` se diferencia por oferecer chaves protegidas por **módulo de hardware**, recurso voltado a cenários com exigência regulatória específica, que não é o caso.

A cobrança é por operação e o volume esperado é baixo, já que as aplicações leem os segredos apenas na inicialização.

### Log Analytics Workspace

Utilizaria o modelo `pay as you go`, com retenção de **30 dias**.

A retenção de até 31 dias não gera custo adicional, então manter 30 dias é o melhor aproveitamento da **janela gratuita**. Períodos maiores só se justificariam por exigência de auditoria.

Configuraria também um **limite diário de ingestão**. A cobrança é por volume de dados coletados, e uma aplicação com erro em loop pode gerar um custo desproporcional em poucas horas. O limite funciona como proteção contra esse tipo de situação.

### Private Endpoints

Este é o item que mais me chamou atenção ao estimar os custos. Os quatro `private endpoints` somam aproximadamente **29 dólares** por mês, o mesmo valor do banco de dados e mais que o dobro do Redis.

Existe uma alternativa sem custo, que seria utilizar `service endpoints` com regras de firewall. Nesse modelo o recurso mantém um endereço público, restrito por lista de IPs permitidos.

Mesmo assim, manteria os `private endpoints`. O propósito de um ambiente de homologação é validar a mesma configuração que irá para produção. Se a topologia de rede for diferente entre os dois ambientes, problemas relacionados a conectividade só apareceriam em produção, que é exatamente o que se busca evitar.

### Azure OpenAI

A cobrança é por **token consumido**, o que torna a estimativa dependente do volume de uso. O valor apresentado considera apenas testes funcionais.

Para evitar surpresas, configuraria um limite de **tokens por minuto** na implantação do modelo e um **alerta de orçamento** no grupo de recursos.

## Recursos que poderiam crescer automaticamente

### Crescem sem intervenção

| Recurso | Como cresce | Configuração que eu adotaria |
|---------|-------------|------------------------------|
| `Container App` da API | Escala pelo número de requisições simultâneas | Entre 0 e 5 réplicas, com 50 requisições por réplica |
| `Container App` do front-end | Escala pelo número de requisições simultâneas | Entre 0 e 3 réplicas |
| `Container App` do Worker | Escala pela quantidade de mensagens na fila | Entre 0 e 5 réplicas, uma réplica a cada 20 mensagens |
| `Storage Account` | Capacidade elástica por natureza | Sem limite a configurar |
| `Log Analytics` | Ingestão elástica | Limite diário definido |
| `Key Vault` e `Azure OpenAI` | Cobrança por uso | Alerta de orçamento configurado |

### Exigem mudança manual de SKU

| Recurso | Como aumentar |
|---------|---------------|
| `Azure SQL Database` | Alteração do tier, por exemplo de `S1` para `S2`. A operação é feita **sem indisponibilidade** |
| `Azure Managed Redis` | Alteração da SKU, por exemplo de `B0` para `B1` |
| `Azure Container Registry` | Alteração do tier, caso a capacidade de download simultâneo passe a limitar as publicações |

Nesses três casos, os alertas configurados na parte de observabilidade serviriam como indicativo de quando o aumento seria necessário. O alerta de `DTU` do banco acima de **80%**, por exemplo, é o sinal de que o `S1` está próximo do limite.

### Observação sobre o `scale to zero`

Manter as aplicações com **zero réplicas** quando não há uso reduz bastante o custo, mas tem uma contrapartida: a primeira requisição após um período ocioso demora alguns segundos, porque a réplica precisa ser iniciada.

Em homologação isso é aceitável. Em produção, eu manteria pelo menos uma réplica ativa na API para eliminar essa espera, assumindo o custo correspondente.

## Estratégias de redução de custo

As escolhas descritas acima já incorporam algumas decisões voltadas a custo. Reúno aqui as principais:

* **Zero réplicas fora do horário de uso**, o que elimina a maior parte do custo de processamento
* **Redis sem alta disponibilidade**, adequado para ambientes que não são de produção
* **Replicação `LRS` em vez de `GRS`** no armazenamento
* **Tier `Basic` no registry** em vez de `Premium`
* **Retenção de logs em 30 dias**, aproveitando a janela sem custo adicional
* **Limite diário de ingestão de logs**, como proteção contra volume inesperado
* **Um único `Container Apps Environment` e um único workspace de logs** compartilhados pelos três componentes, em vez de recursos separados por aplicação
* **Alertas de orçamento no grupo de recursos**, para acompanhar o gasto antes que ele apareça na fatura

Uma prática adicional que consideraria é desligar o ambiente fora do horário comercial por meio de uma automação agendada. Como as aplicações já operam com zero réplicas, o ganho adicional viria de **pausar o banco de dados**, o que exigiria mudar para o modelo `Serverless` do `Azure SQL`. Avaliaria essa mudança apenas se o ambiente ficasse ocioso por períodos longos entre ciclos de teste.

## Fontes e método de cálculo

### Como cheguei aos valores

Os números apresentados vêm de duas origens distintas, e considero importante separá-las:

**Tarifas oficiais**, consultadas nas páginas de preço da `Azure` em agosto de 2026:

| Serviço | Tarifa de referência |
|---------|----------------------|
| `Container Apps` (`Consumption`) | 0,000024 dólar por `vCPU`-segundo e 0,000003 dólar por `GiB`-segundo, com 180.000 `vCPU`-segundos, 360.000 `GiB`-segundos e 2 milhões de requisições gratuitos por mês |
| `Log Analytics` | 2,30 dólares por GB, após 5 GB gratuitos por mês |
| `Container Registry Basic` | 0,167 dólar por dia, com 10 GB inclusos |
| `Azure SQL Standard` | `S0` a 0,0202 dólar por hora e `S2` a 0,0805 dólar por hora |

**Totais mensais calculados**, aplicando essas tarifas às premissas de uso descritas no início deste documento. Os valores da coluna de custo mensal são resultado desse cálculo, e **não preços publicados**.

Um exemplo de como cheguei ao valor do `Container Apps`: considerando as três aplicações ativas dentro da janela de uso assumida, o consumo estimado fica pouco acima da cota gratuita mensal, resultando em aproximadamente **8 dólares**. Com um padrão de uso diferente, esse número mudaria bastante.

O valor da SKU `S1` do banco foi estimado por **interpolação** entre o `S0` e o `S2`, que são as duas referências que consultei diretamente.

### Páginas de referência

| Serviço | Endereço |
|---------|----------|
| `Container Apps` | https://azure.microsoft.com/pricing/details/container-apps/ |
| `Azure SQL Database` | https://azure.microsoft.com/pricing/details/azure-sql-database/single/ |
| `Container Registry` | https://azure.microsoft.com/pricing/details/container-registry/ |
| `Azure Monitor` e `Log Analytics` | https://azure.microsoft.com/pricing/details/monitor/ |
| `Key Vault` | https://azure.microsoft.com/pricing/details/key-vault/ |
| `Storage Account` | https://azure.microsoft.com/pricing/details/storage/blobs/ |
| `Private Link` | https://azure.microsoft.com/pricing/details/private-link/ |
| `Azure DNS` | https://azure.microsoft.com/pricing/details/dns/ |
| `Azure OpenAI` | https://azure.microsoft.com/pricing/details/cognitive-services/openai-service/ |
| Calculadora de preços | https://azure.microsoft.com/pricing/calculator/ |

### Ressalvas sobre os preços

Os preços da `Azure` mudam com frequência e variam por região. Todas as tarifas acima são da região `East US`, escolhida por ser a referência mais comum nas páginas de preço.

Para um orçamento real, eu montaria a estimativa diretamente na calculadora de preços da `Azure`, selecionando a região definitiva e o compromisso de uso aplicável. O objetivo deste documento é **dimensionar a arquitetura** e apresentar a **ordem de grandeza** do custo, não produzir uma cotação.

## Limitações desta estimativa

Considero importante registrar o que esta estimativa **não cobre**:

* Os valores são **preços de lista** e não consideram descontos por compromisso de uso ou acordos comerciais
* A conversão para `Brazil South` é uma **aproximação**, não um valor consultado
* O custo do `Azure OpenAI` depende diretamente do volume de uso, que não é conhecido
* Não estão considerados custos de **tráfego de saída de dados**, que dependem do padrão de acesso
* O dimensionamento assume um ambiente de homologação. Um ambiente de produção exigiria revisão completa das SKUs, com **alta disponibilidade** no Redis, **redundância de zona** no banco e **réplicas mínimas ativas** nas aplicações

Em um projeto real, eu apresentaria esses valores como estimativa inicial e faria o acompanhamento pelo `Azure Cost Management` durante os primeiros meses, ajustando as SKUs com base no consumo observado.
