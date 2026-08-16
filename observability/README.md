# Observabilidade

Corresponde à **Parte 8** do teste técnico.

Este documento descreve como eu implementaria a observabilidade da aplicação, cobrindo **logs centralizados**, **métricas**, **dashboards**, **alertas**, **rastreamento distribuído** e **análise de exceções**.

A proposta parte de um princípio simples: escolher o **menor número de serviços** que resolva todas as necessidades. O cenário do teste não informa volume de usuários, tamanho do time nem escala esperada, então evitei assumir uma infraestrutura grande. Organizei a escolha por necessidade (logs, métricas, dashboards, rastreamento, análise de exceções e alertas) e defini um único serviço responsável por cada uma, em vez de ter mais de uma ferramenta cobrindo a mesma coisa.

Minha experiência prática em observabilidade vem principalmente de `Prometheus` e `Grafana`. Por isso, sempre que houver um equivalente claro, faço a comparação. Isso ajuda a situar a escolha em algo que já conheço, não só no nome do serviço.

> [!TIP]
> Se você já conhece a stack `Prometheus`/`Grafana`, a subseção **Relação com ferramentas conhecidas** de cada tópico traz o equivalente direto: é o atalho mais rápido para entender a escolha.

## Logs centralizados

**Serviço escolhido:** `Azure Log Analytics Workspace`

### Como eu utilizaria

Configuraria um único workspace para todo o ambiente de homologação, recebendo logs de duas origens:

* **Aplicações:** o `Container Apps Environment` envia automaticamente a saída padrão dos containers para o workspace. Não seria necessário instalar agente nem configurar coleta manual.

* **Infraestrutura:** habilitaria `diagnostic settings` nos recursos que já provisionei no `Terraform`, apontando para o mesmo workspace. Isso cobriria `Azure SQL Database`, `Key Vault`, `Storage Account` e `Azure Container Registry`.

Para consultar os logs utilizaria `KQL`, a linguagem de consulta do `Azure Monitor`.

### Por que eu escolheria

O `Log Analytics` é o destino nativo de logs dos serviços que usei neste cenário (`Container Apps`, `SQL Database`, `Key Vault`, `Storage Account`, `Container Registry`). Usar outra solução exigiria exportar os dados para fora da plataforma, o que adicionaria um componente de coleta a manter sem trazer benefício.

Manteria **um único workspace** compartilhado pelos três componentes, em vez de um por aplicação. Isso permite correlacionar em uma mesma consulta um erro da API com o comportamento do `Worker` no mesmo intervalo de tempo, algo que ficaria inviável com repositórios separados.

Definiria também um **limite diário de ingestão**. Acredito que a cobrança é por volume de dados no Azure, e um erro em loop pode gerar um custo desproporcional em poucas horas.

> [!WARNING]
> Sem um limite diário de ingestão configurado, um erro em loop pode multiplicar o volume de logs enviado e gerar um custo inesperado em poucas horas.

### Relação com ferramentas conhecidas

O papel do `Log Analytics` é o mesmo que o `Loki` cumpre em uma stack `Grafana`: centralizar logs de várias origens e permitir consultá-los por período e por filtros. A diferença prática é que o `KQL` é mais próximo de uma linguagem de consulta analítica, enquanto o `LogQL` do `Loki` é mais direto para filtragem.

## Métricas

**Serviço escolhido:** `Azure Monitor`

### O que eu acompanharia

Acompanharia dois níveis de métricas:

* **Infraestrutura:** número de réplicas ativas dos `Container Apps`, consumo de CPU e memória, `DTU` do `SQL Database`, uso de memória do `Redis` e profundidade da fila do `Storage Queue`.

* **Aplicação:** tempo de resposta por endpoint, taxa de falhas e volume de requisições, coletados pelo `Application Insights`.

As métricas de plataforma são coletadas automaticamente pelo `Azure Monitor`, sem necessidade de configuração.

### O que pesou na escolha

As métricas de plataforma já estão disponíveis por padrão e aparentemente não possuem custo adicional. Introduzir outra ferramenta de coleta significaria manter um componente extra para obter dados que a própria plataforma já expõe.

> [!IMPORTANT]
> A **profundidade da fila** é a métrica que dispara o autoscaling do `Worker`. Acompanhá-la ajuda a diferenciar dois cenários parecidos: mais réplicas por aumento real de carga, ou mais réplicas porque as mensagens não estão sendo consumidas.

### Relação com ferramentas conhecidas

A função é a mesma que o `Prometheus` cumpre: coletar e armazenar séries temporais para acompanhamento e alerta.

A diferença está no modelo de coleta. O `Prometheus` trabalha por `scraping`, consultando periodicamente um endpoint exposto pela aplicação. O `Azure Monitor` recebe as métricas emitidas pelos próprios recursos. Na prática, isso elimina a necessidade de configurar targets e endpoints de métricas, mas também dá menos controle sobre quais métricas customizadas são expostas.

## Dashboards

**Serviço escolhido:** `Azure Workbooks`

### O que eu criaria

Criaria dois workbooks:

* **Visão geral da aplicação:** requisições por minuto, tempo médio de resposta, taxa de erro e número de réplicas ativas de cada componente.

* **Visão de infraestrutura:** `DTU` do `SQL Database`, memória do `Redis`, profundidade da fila e volume de logs ingeridos.

Os workbooks combinam consultas `KQL` e gráficos de métricas no mesmo painel, o que permite colocar lado a lado um gráfico de erros e a consulta que lista as exceções daquele período.

### Por que os Workbooks e não o Grafana

Os `Workbooks` já estão incluídos no `Azure Monitor`, sem custo adicional e sem serviço novo a provisionar.

Considerei usar o `Grafana` gerenciado do Azure, já que tenho mais familiaridade com ele. Descartei porque traria custo de instância e entregaria essencialmente a mesma capacidade de visualização. Faria sentido em dois cenários: se o time já tivesse dashboards `Grafana` em uso, ou se fosse necessário reunir dados de várias nuvens em um painel único. Nenhum dos dois se aplica ao cenário do teste.

Foi aqui que mais conscientemente troquei a ferramenta que conheço melhor pela mais simples para o cenário.

### Relação com ferramentas conhecidas

Os `Workbooks` ocupam o lugar do `Grafana`. São menos flexíveis em personalização visual e têm um ecossistema de dashboards prontos bem menor. Em compensação, já vêm integrados às fontes de dados e não exigem configurar datasources nem manter uma instância.

## Rastreamento distribuído

**Serviço escolhido:** `Application Insights`

### Como eu instrumentaria

Adicionaria o SDK do `Application Insights` aos projetos `.NET` da API e do `Worker`, e configuraria a `connection string` por variável de ambiente, resolvida a partir do `Key Vault`.

Com isso seria possível acompanhar uma requisição desde a chamada do front-end, passando pela API, pelo acesso ao banco e ao `Redis`, até o processamento assíncrono no `Worker`. A visualização do mapa de dependências mostra qual etapa consumiu mais tempo.

No front-end `Angular`, utilizaria a versão web do SDK para capturar erros de JavaScript e tempo de carregamento das páginas.

### Por que essa é a exceção da lista

O rastreamento distribuído é a única necessidade da lista que não tem alternativa simples dentro do Azure. Sem ele, ao investigar uma requisição lenta seria preciso comparar manualmente logs de três componentes tentando reconstruir a ordem dos acontecimentos.

O ganho concreto no cenário está no fluxo assíncrono: a API publica uma mensagem na fila e o `Worker` a consome depois. Sem correlação entre os dois, essas operações apareceriam como eventos desconexos.

> [!IMPORTANT]
> O `Application Insights` **não tem cobrança própria**. A telemetria é faturada pela ingestão do mesmo `Log Analytics Workspace` já utilizado para os logs, o que evita um segundo medidor de custo.

### Relação com ferramentas conhecidas

A função equivale à do `Jaeger` em uma stack open source. A diferença prática mais relevante é que o `Application Insights` instrumenta automaticamente chamadas HTTP, acessos a banco de dados e operações de fila, sem exigir instrumentação manual no código.

## Análise de exceções

**Serviço escolhido:** `Application Insights`

### Como funcionaria no dia a dia

O mesmo SDK que coleta os traces captura automaticamente as exceções não tratadas, agrupando-as por tipo e por local no código. Para cada exceção fica registrado o número de ocorrências, a versão da aplicação em que ocorreu e o trace completo da requisição que a originou.

Utilizaria principalmente para dois propósitos: identificar qual erro é mais frequente antes de decidir o que corrigir primeiro, e verificar se um erro novo começou a aparecer logo após um deploy.

### Por que não somar outra ferramenta

Não adicionaria uma ferramenta específica de rastreamento de erros, porque o `Application Insights` já cobre a necessidade. Manter duas ferramentas significaria alternar entre elas durante a investigação de um mesmo problema, justamente no momento em que a informação precisa estar reunida.

A vantagem de a análise de exceções e o rastreamento distribuído virem do mesmo serviço é poder partir de uma exceção e chegar ao trace completo da requisição, incluindo as chamadas que a antecederam.

### Relação com ferramentas conhecidas

Cumpre o papel das ferramentas dedicadas de rastreamento de erros: agrupar exceções repetidas, mostrar frequência e apontar a versão afetada. Esse tipo de ferramenta costuma oferecer uma experiência mais refinada para essa tarefa específica; o `Application Insights` compensa por já estar integrado ao restante da telemetria.

## Alertas

**Serviço escolhido:** `Azure Monitor Alerts` com `Action Groups`

### Quais alertas eu configuraria

Configuraria um conjunto pequeno de alertas, cada um ligado a um sintoma que exigiria ação:

| Alerta | Condição | Motivo |
|--------|----------|--------|
| Taxa de erro da API | Acima de 5% por 5 minutos | Indica falha afetando usuários |
| DTU do `SQL Database` | Acima de 80% por 10 minutos | Antecede o esgotamento tratado no Cenário E |
| Fila sem consumo | Profundidade crescente com `Worker` sem réplicas ativas | Indica Worker travado ou com falha de escala |
| Réplicas no limite máximo | `Container App` no máximo de réplicas por 15 minutos | Pode indicar carga real ou o problema do Cenário C |
| Volume de logs | Próximo do limite diário de ingestão | Evita perda de logs e custo inesperado |

As notificações seriam entregues por um `Action Group` configurado para e-mail e `Microsoft Teams`.

### O critério para os alertas

> [!CAUTION]
> Alertas em excesso levam ao efeito contrário do pretendido: quando muitos disparam sem exigir ação, a equipe passa a ignorá-los, e o alerta que realmente importa se perde no meio.

Manteria a lista curta de propósito.

O critério que aplicaria para criar um alerta é se existe uma **ação clara** a tomar quando ele disparar. Um alerta sem resposta definida é apenas ruído.

> [!NOTE]
> Para o ambiente de homologação, usaria limites mais tolerantes do que usaria em produção. Homologação recebe testes de carga e deploys frequentes, então alertas muito sensíveis disparariam por comportamento esperado.

### Relação com ferramentas conhecidas

A estrutura é a mesma do `Alertmanager` no ecossistema `Prometheus`: uma regra avalia uma condição sobre uma métrica e, quando satisfeita, encaminha a notificação para um canal. O `Action Group` cumpre o papel do `receiver` do `Alertmanager`.

## Como os recursos trabalham em conjunto

Os serviços escolhidos cobrem etapas diferentes da investigação de um problema:

* **O alerta avisa que algo está errado.** Sem ele, o problema só seria descoberto quando alguém reportasse.

* **As métricas mostram a dimensão.** Indicam quando começou, se está piorando e quais componentes foram afetados.

* **O dashboard dá o contexto.** Permite verificar se outros indicadores mudaram no mesmo período, o que ajuda a separar causa de consequência.

* **O rastreamento distribuído aponta onde.** Mostra qual etapa da requisição está lenta ou falhando, atravessando os três componentes.

* **A análise de exceções aponta o quê.** Identifica o erro específico e o ponto do código.

* **Os logs completam a investigação.** Trazem o detalhe que a telemetria estruturada não captura.

Um exemplo do fluxo no cenário do teste: o alerta de taxa de erro da API dispara. No dashboard, fica visível que a DTU do `SQL Database` subiu no mesmo período. O rastreamento distribuído mostra que as requisições estão lentas na chamada ao banco. A análise de exceções identifica exceções de timeout de conexão. Os logs do `SQL Database` confirmam o esgotamento de recursos.

A observação relevante é que esse encadeamento acontece **sem trocar de ferramenta**. Todos os dados estão no mesmo `Log Analytics Workspace`, o que permite consultá-los em conjunto.

## Serviços que eu não utilizaria

Registro as alternativas que considerei e descartei, junto com a condição que me faria mudar de ideia:

| Serviço | Motivo de descartar | Quando eu reconsideraria |
|---------|---------------------|--------------------------|
| `Azure Managed Grafana` | Custo de instância para entregar o que os `Workbooks` já entregam | Se o time já tivesse dashboards Grafana ou precisasse unificar múltiplas nuvens |
| `Azure Monitor managed Prometheus` | Voltado a cargas em Kubernetes; o `Container Apps` já envia métricas ao `Azure Monitor` | Se a solução migrasse para `AKS` |
| Coletor `OpenTelemetry` dedicado | Adiciona um componente a operar; o SDK envia a telemetria diretamente | Se fosse necessário enviar telemetria para múltiplos destinos |
| Ferramenta externa de `APM` | Custo e integração adicionais sem ganho no cenário | Se a empresa já tivesse contrato e padronização em uma delas |
| Ferramenta dedicada de rastreamento de erros | O `Application Insights` já cobre a necessidade | Se o time precisasse de fluxo de triagem de erros mais elaborado |

O raciocínio foi o mesmo em todos os casos: cada necessidade do cenário já tinha um serviço responsável por ela, um serviço adicional só entraria se sobrasse alguma necessidade sem cobertura.

## Observação sobre a implementação

O `Log Analytics Workspace` e o `Application Insights` já estão provisionados no módulo `monitoring` do `Terraform`, com retenção de 30 dias e limite diário de ingestão configurado. As `diagnostic settings` dos demais recursos apontam para o mesmo workspace.

> [!IMPORTANT]
> Os workbooks, alertas e action groups descritos aqui **não foram implementados em código**. Em um projeto real, eu os provisionaria também por Terraform, para manter a configuração versionada junto do restante da infraestrutura.

## Glossário de siglas

| Sigla | Significado |
|-------|-------------|
| `AKS` | Azure Kubernetes Service |
| `APM` | Application Performance Monitoring |
| `DTU` | Database Transaction Unit |
| `KQL` | Kusto Query Language |
| `LogQL` | Log Query Language |
| `SDK` | Software Development Kit |
