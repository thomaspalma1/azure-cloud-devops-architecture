# Integração com Inteligência Artificial

Corresponde à **Parte 9** do teste técnico.

O enunciado indica que a empresa pretende utilizar o `Azure AI Foundry` para integrar modelos `GPT` aos seus produtos. Este documento apresenta como eu faria essa integração, onde armazenaria os `prompts`, como protegeria as credenciais e como acompanharia consumo e custos.

## Observação sobre esta proposta

Considero importante ser **transparente** quanto ao meu nível de conhecimento neste tema.

**Não tenho experiência profissional** com integração de Inteligência Artificial, nem com o `Azure AI Foundry` especificamente. O que apresento aqui é fruto de pesquisa na documentação oficial da Microsoft e em materiais técnicos sobre o assunto, não de uma implementação que eu tenha conduzido na prática.

Por esse motivo, mantive a proposta **deliberadamente simples**. Existem diferentes formas de estruturar uma solução com IA, e não apresento esta como a única correta ou a mais adequada. Ela representa o que eu proporia como ponto de partida para o cenário do teste, com a expectativa de refiná-la conforme o time definisse os requisitos reais de uso.

Onde identifiquei decisões que exigiriam mais conhecimento do que possuo hoje, registrei isso **explicitamente** ao longo do documento.

## Entendimento dos serviços

Antes de descrever a arquitetura, registro como entendi a relação entre os serviços mencionados, já que os nomes se confundem com facilidade:

* `Azure AI Foundry` é a **plataforma unificada** para construir, testar e publicar aplicações de IA. Sucede o antigo `Azure AI Studio` e organiza os recursos em `Hubs` e `Projects`.
* `Azure OpenAI` é um dos serviços disponíveis dentro do `Foundry`, e é ele que dá acesso aos modelos `GPT`.
* Na prática, o `Foundry` é o ambiente onde o modelo é escolhido e implantado, e a aplicação consome esse modelo por meio de um `endpoint` gerado após a implantação.

Ou seja, os dois **não são alternativas concorrentes**. O `Foundry` é a camada de plataforma, e o `Azure OpenAI` é o serviço de modelos que ela disponibiliza.

## Arquitetura

### Como eu organizaria

A integração seguiria o seguinte fluxo:

* **Camada de plataforma**
  * Criaria um projeto no `Azure AI Foundry` dentro do grupo de recursos do ambiente
  * Implantaria o modelo escolhido, gerando um `endpoint` dedicado
* **Chamadas síncronas**
  * A API em `.NET` seria responsável por chamar o `endpoint` do modelo
  * Utilizaria esse caminho para operações rápidas, em que o usuário aguarda a resposta
* **Chamadas assíncronas**
  * O `Worker` consumiria mensagens da fila e faria as chamadas mais demoradas
  * Utilizaria esse caminho para operações que processam volumes maiores de texto
* **Front-end**
  * O `Angular` **nunca** chamaria o modelo diretamente
  * Toda comunicação passaria pela `API`

### Por que o front-end não chamaria o modelo diretamente

Esta é a **decisão mais importante** desta seção, e a que eu defenderia com mais convicção.

Qualquer credencial entregue ao navegador é **pública**, porque o usuário pode inspecioná-la. Se o `Angular` chamasse o `endpoint` diretamente, a credencial de acesso ao modelo ficaria exposta, e qualquer pessoa poderia utilizá-la para consumir tokens pagos pela empresa.

Mantendo a chamada na `API`, a credencial permanece no servidor e é possível aplicar controles antes de repassar a requisição ao modelo, como verificar se o usuário está autenticado e limitar a quantidade de requisições por usuário.

### Por que separar chamadas síncronas e assíncronas

Chamadas a modelos de linguagem costumam demorar mais que chamadas convencionais a banco de dados. Se todas fossem síncronas, uma operação que processa um documento longo poderia manter a requisição `HTTP` aberta por bastante tempo, ocupando uma réplica da `API`.

Como a solução já possui um `Worker` e uma fila, aproveitaria essa estrutura que já existe em vez de introduzir um componente novo. A `API` publicaria a solicitação na fila, responderia imediatamente ao usuário e o `Worker` faria o processamento.

Registro que esse limite entre o que seria síncrono e o que seria assíncrono dependeria do **caso de uso real**, que o teste não especifica.

## Armazenamento dos prompts

### Onde eu armazenaria

Manteria os `prompts` em arquivos de texto dentro do repositório da aplicação, **versionados junto com o código**.

Organizaria em uma pasta dedicada, com um arquivo por `prompt`, e carregaria o conteúdo na inicialização da aplicação.

### Por que versionar no repositório

`Prompt` é conteúdo que define o comportamento da aplicação, de forma semelhante ao código. Mantê-lo versionado traz três benefícios diretos:

* O histórico de alterações fica registrado, permitindo identificar quando um `prompt` mudou
* As alterações passam por `Pull Request` e são revisadas como qualquer outra mudança
* É possível relacionar uma mudança de comportamento do modelo com a alteração que a causou

Considerei e descartei duas alternativas:

* **Armazenar no Key Vault:** o `Key Vault` é para segredos, e `prompt` **não é segredo**. Além disso, ele não oferece histórico de alterações adequado para esse tipo de conteúdo.
* **Armazenar em banco de dados:** permitiria alterar o `prompt` sem novo `deploy`, mas abriria mão da revisão por `Pull Request` e do histórico versionado. Avaliaria essa opção apenas se surgisse a necessidade de pessoas fora do time técnico ajustarem os `prompts`.

### Limitação que reconheço

O `Azure AI Foundry` oferece uma ferramenta chamada `Prompt Flow`, voltada à criação e ao teste de fluxos com modelos de linguagem. Pelo que pesquisei, ela permite versionar e avaliar `prompts` dentro da própria plataforma.

**Não tenho conhecimento suficiente** para afirmar se ela seria mais adequada que a abordagem por arquivos no repositório. Seria um dos pontos que eu estudaria antes de fechar a decisão, especialmente se o time precisasse comparar versões de `prompt` e medir qual gera melhores resultados.

## Proteção das credenciais

### Como protegeria as credenciais

Utilizaria `Managed Identity` para autenticar a `API` e o `Worker` no serviço de IA, da mesma forma que já é feito para o banco de dados e o `storage` nesta solução.

Com `Managed Identity`, a aplicação obtém o acesso a partir da identidade que ela já possui no `Entra ID`, e **não existe chave a ser armazenada**.

Caso a `Managed Identity` não fosse suportada para alguma operação específica, armazenaria a chave no `Key Vault` e a leria em tempo de execução, **nunca** a colocando em arquivo de configuração ou variável de ambiente com valor fixo.

### Por que usar Managed Identity

Adotaria a mesma abordagem já utilizada no restante da solução, o que traz **coerência** e evita introduzir um modelo de autenticação diferente apenas para este serviço.

A vantagem prática é que, sem chave, **não existe credencial para rotacionar, vazar ou aparecer acidentalmente em um repositório**.

Reforço o ponto da seção de arquitetura: independentemente do mecanismo escolhido, a credencial **nunca** chegaria ao front-end.

## Monitoramento do consumo

### Como acompanharia o consumo

Aproveitaria os recursos já definidos na parte de observabilidade, sem adicionar ferramenta nova:

* **Métricas do serviço**
  * Acompanharia o número de `tokens` consumidos e a quantidade de requisições pelas métricas disponíveis no `Azure Monitor`
* **Telemetria da aplicação**
  * O `Application Insights` já registra as chamadas que a aplicação faz a serviços externos, o que permitiria acompanhar tempo de resposta e falhas nas chamadas ao modelo
* **Alertas**
  * Configuraria um alerta para consumo de `tokens` acima do esperado em um intervalo de tempo
  * Configuraria um alerta para taxa de erro nas chamadas ao modelo

### Por que focar no consumo de tokens

O **consumo de tokens** é a informação central, porque é ela que determina o custo. Acompanhar apenas o número de requisições não seria suficiente, já que uma única requisição com muito texto pode consumir mais que várias requisições curtas.

Como o `Application Insights` já estará instrumentado na `API` e no `Worker`, as chamadas ao modelo apareceriam automaticamente como dependências externas, sem necessidade de configuração adicional.

## Controle de custos

### Como controlaria os custos

Adotaria quatro medidas:

* **Limite de tokens por minuto na implantação**
  * Ao implantar o modelo, é possível definir uma cota de `tokens` por minuto
  * Esse limite funciona como **teto técnico**: mesmo que algo consuma mais que o previsto, o consumo não ultrapassa o valor definido
* **Alerta de orçamento no grupo de recursos**
  * Configuraria alertas em percentuais do valor previsto, para acompanhar o gasto antes do fechamento da fatura
* **Escolha de um modelo menor como padrão**
  * Utilizaria um modelo de menor custo como opção inicial, avaliando um modelo maior apenas para os casos em que a qualidade da resposta se mostrasse insuficiente
* **Controle de uso por usuário na API**
  * Limitaria a quantidade de requisições que um mesmo usuário pode fazer em determinado intervalo

### Por que essas medidas

O **limite de tokens por minuto** é a medida mais importante, porque é a única que efetivamente impede o gasto. As demais são de acompanhamento: elas avisam que o custo está subindo, mas **não o interrompem**.

Sobre a escolha do modelo, a diferença de preço entre os modelos disponíveis é significativa. Como o cenário do teste não especifica qual seria o uso da IA no produto, começar pelo modelo mais econômico e ajustar conforme a necessidade me parece mais razoável do que escolher o modelo mais capaz por antecipação.

### Limitação que reconheço

**Não tenho experiência prática** para estimar o consumo real de `tokens` de uma aplicação, porque isso depende do tipo de uso, do tamanho dos textos processados e do volume de requisições.

Por esse motivo, na parte de dimensionamento apresentei o custo do serviço de IA como uma **faixa ampla**, e não como um valor preciso. Em um projeto real, eu acompanharia o consumo nas primeiras semanas para chegar a uma estimativa com base em dado observado.

## Resumo das decisões

| Ponto | Decisão | Justificativa principal |
|-------|---------|-------------------------|
| Arquitetura | Chamadas feitas pela `API` e pelo `Worker`, nunca pelo front-end | Evita expor credenciais no navegador |
| Chamadas demoradas | Processadas pelo `Worker` por meio da fila | Aproveita estrutura já existente na solução |
| Prompts | Arquivos versionados no repositório | Permite histórico e revisão por `Pull Request` |
| Credenciais | `Managed Identity`, com `Key Vault` como alternativa | Mantém coerência com o restante da solução e elimina chaves |
| Monitoramento | `Azure Monitor` e `Application Insights` | Reaproveita os recursos já definidos em observabilidade |
| Custos | Limite de `tokens` por minuto, alertas de orçamento e modelo econômico como padrão | O limite técnico é a única medida que efetivamente impede gasto excessivo |

## O que eu estudaria antes de implementar

Registro aqui os pontos que eu precisaria aprofundar antes de partir para uma implementação real:

* O funcionamento do `Prompt Flow` e se ele substituiria a abordagem de `prompts` versionados no repositório
* As diferenças entre os tipos de implantação disponíveis, que segundo a documentação afetam custo, latência e local de processamento dos dados
* Como estimar consumo de `tokens` a partir do caso de uso, para produzir um dimensionamento de custo mais preciso
* Boas práticas de tratamento de erro específicas de chamadas a modelos de linguagem, como comportamento diante de limite de requisições atingido
* Recursos de IA responsável oferecidos pela plataforma, como filtros de conteúdo

Considero que reconhecer esses pontos é parte de propor uma **solução honesta**. Preferi apresentar uma proposta simples que consigo explicar por completo a apresentar uma arquitetura mais elaborada que eu não saberia sustentar.
