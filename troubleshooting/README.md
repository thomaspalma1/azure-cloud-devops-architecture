# Resolução de Problemas

Corresponde à **Parte 10** do teste técnico.

Este documento apresenta como eu investigaria cada um dos cenários propostos, considerando a arquitetura definida neste projeto.

## Observação sobre a abordagem

Em todos os cenários segui o mesmo raciocínio: **começar pela informação mais barata de obter** e só depois avançar para verificações mais trabalhosas.

Na prática, isso significa olhar primeiro os logs e as métricas que já estão sendo coletados, antes de reproduzir o problema ou alterar configurações. Como a solução já envia toda a telemetria para um único `Log Analytics Workspace`, boa parte das respostas estaria disponível sem precisar acessar cada recurso individualmente.

Sempre que possível, indiquei também **como a causa apontada se relaciona com decisões tomadas neste projeto**, já que conhecer a própria arquitetura costuma encurtar bastante a investigação.

## Cenário A: o Container App não inicia após o deploy

### Como eu descobriria a causa

#### Primeiro passo: verificar o estado da revisão

Consultaria o estado da revisão criada pelo deploy. O `Container Apps` mostra se ela está em execução, se falhou ao iniciar ou se está reiniciando repetidamente.

Esse dado já separa dois casos bem diferentes: um container que **nunca subiu** e um container que **sobe e cai logo em seguida**.

#### Segundo passo: consultar os logs do container

Buscaria no `Log Analytics` os logs da revisão que falhou. A saída padrão do container é enviada automaticamente para o workspace, então a mensagem de erro da aplicação estaria disponível ali.

#### Terceiro passo: verificar as causas prováveis na inicialização

Com base em como a solução foi construída, verificaria nesta ordem:

* **Falha ao resolver segredos do `Key Vault`**
  * Esta é a causa que eu investigaria primeiro, porque envolve duas partes que precisam estar corretas ao mesmo tempo
  * Verificaria se a `Managed Identity` da aplicação possui a permissão de leitura de segredos
  * Verificaria se o nome do segredo referenciado existe no `Key Vault`
  * Nesse caso o container falha na inicialização, antes de registrar qualquer log da aplicação
* **Falha ao baixar a imagem do registry**
  * Verificaria se a `tag` da imagem realmente existe no `Azure Container Registry`
  * Verificaria se a identidade possui a permissão `AcrPull`
* **Porta divergente entre o container e o `ingress`**
  * A aplicação pode subir corretamente, mas nunca receber tráfego se a porta configurada no `ingress` não for a mesma que a aplicação escuta
  * Nesta solução, tanto as aplicações `.NET` quanto o `nginx` escutam na porta `8080`
* **Falha do `health probe`**
  * Se o `probe` aponta para um caminho que não responde, a plataforma considera a réplica não saudável e reinicia o container em ciclo
  * Nesta solução, o caminho configurado é `/healthz`

### Limitação imposta pelas imagens distroless

As imagens `.NET` utilizam variantes `distroless`, que **não possuem shell**. Isso significa que não é possível abrir um terminal dentro do container para investigar.

Essa é uma consequência assumida da decisão de segurança tomada na parte de Docker. A investigação depende inteiramente dos logs e das métricas, e por isso é importante que a aplicação registre mensagens claras durante a inicialização.

## Cenário B: a API não consegue acessar o Redis

### Como eu isolaria a camada da falha

#### Primeiro passo: identificar o tipo de falha

Consultaria os logs da API para verificar a mensagem de erro. A distinção mais importante é entre:

* **Falha de resolução de nome**: quando o endereço não é encontrado
* **Falha de conexão**: quando o endereço é resolvido mas a conexão não é estabelecida
* **Falha de autenticação**: quando a conexão acontece mas é recusada

Cada uma aponta para uma camada diferente do problema.

#### Segundo passo: verificar as causas prováveis na conexão

* **Porta incorreta**
  * Começaria por aqui, porque é a verificação mais rápida de todas
  * O `Azure Managed Redis` utiliza a porta `10000`, e não a `6380` do `Azure Cache for Redis`. Confirmaria esse valor na documentação do produto antes de descartar a hipótese
  * Como este projeto adotou o `Azure Managed Redis`, uma configuração copiada de outro projeto ou de material antigo apontaria para a porta errada
* **Configuração do `private endpoint`**
  * O `Redis` foi configurado sem acesso público, então a conexão depende do `private endpoint` funcionar corretamente
  * Verificaria se o `private endpoint` está aprovado e se a zona de DNS privada está vinculada à `virtual network`
  * Verificaria também para qual endereço o nome está resolvendo: se ele resolver para um endereço público, o problema está no DNS, e não no `Redis`
* **Valor do segredo no `Key Vault`**
  * Verificaria se o endereço armazenado está correto e se a API está lendo o segredo esperado
* **Estado do recurso**
  * Verificaria se a instância está disponível e se há registro de manutenção no período

### Efeito da configuração sem alta disponibilidade

O `Redis` deste projeto foi provisionado **sem alta disponibilidade**, decisão tomada na parte de dimensionamento para reduzir custo em ambiente de homologação.

Isso significa que uma manutenção da plataforma pode causar indisponibilidade temporária. Se a falha for intermitente e coincidir com janelas de manutenção, essa seria uma explicação plausível, e não um defeito de configuração.

## Cenário C: o Container App está escalando para dezenas de réplicas inesperadamente

### Como eu identificaria a origem do crescimento

#### Primeiro passo: identificar qual regra disparou o crescimento

Nesta solução, as aplicações escalam por critérios diferentes, então a primeira pergunta é **qual aplicação** está escalando:

* A API e o front-end escalam pelo número de requisições simultâneas
* O Worker escala pela quantidade de mensagens na fila

Essa distinção direciona toda a investigação seguinte.

#### Segundo passo: se for a API ou o front-end

Verificaria o volume de requisições no período, usando as métricas do `Application Insights`.

* **Se o volume aumentou de fato**, o crescimento é o comportamento esperado, e a pergunta passa a ser de onde vem o tráfego
* **Se o volume não aumentou**, investigaria se as requisições estão demorando mais que o normal. Requisições mais lentas mantêm mais conexões abertas ao mesmo tempo, e isso faz a aplicação escalar mesmo sem aumento real de acessos

Neste segundo caso, a causa costuma estar em uma dependência lenta. Consultaria o mapa de dependências do `Application Insights` para verificar se o banco de dados, o `Redis` ou o serviço de IA estão respondendo mais devagar.

#### Terceiro passo: se for o Worker

Verificaria a quantidade de mensagens na fila. As possibilidades são:

* **Volume legítimo de mensagens**, caso alguma operação tenha gerado muitas solicitações de uma vez
* **Mensagens não sendo removidas após o processamento**, o que faz a fila parecer sempre cheia e mantém o crescimento indefinidamente
* **Falha no processamento**, com mensagens retornando à fila repetidamente

O segundo e o terceiro casos são os mais preocupantes, porque o crescimento **não resolve o problema**: as réplicas aumentam, mas a fila não diminui.

### Como eu limitaria o impacto

Nesta solução, cada aplicação possui um número máximo de réplicas configurado, o que já limita o crescimento e, por consequência, o custo.

Também há um alerta configurado para quando uma aplicação permanece no número máximo de réplicas por período prolongado, justamente para detectar essa situação antes que ela apareça na fatura.

## Cenário D: a pipeline falha somente no push da imagem para o Azure Container Registry

### Como eu resolveria a falha no push

O fato de a falha ocorrer **apenas nesta etapa** já elimina boa parte das possibilidades. Se o build da imagem funcionou, o problema não está no `Dockerfile` nem no código.

#### Primeiro passo: verificar a permissão

Esta seria minha primeira suspeita. A identidade utilizada pela pipeline precisa de permissão de escrita no registry, e a permissão de leitura não é suficiente para publicar.

Verificaria se a `service connection` do `Azure DevOps` está associada a uma identidade com a permissão adequada.

#### Segundo passo: verificar a autenticação

Se o projeto utilizasse `service principal` com chave, verificaria se a chave expirou. Esse é um problema clássico, porque a pipeline funciona por meses e falha de repente sem que nada tenha mudado no código.

Neste projeto propus a **federação de credenciais**, justamente para eliminar esse tipo de falha, já que não há chave com prazo de validade.

#### Terceiro passo: verificar o espaço disponível

O registry foi provisionado no tier `Basic`, que inclui **10 GB** de armazenamento. Se o limite for atingido, a publicação passa a falhar.

Verificaria o consumo atual e, se for o caso, removeria imagens antigas ou avaliaria a mudança de tier.

#### Quarto passo: verificar o nome do repositório e a tag

Verificaria se o nome do registry na pipeline corresponde ao registry provisionado e se a `tag` está sendo gerada corretamente a partir da variável de build.

### Como eu evitaria a recorrência

O acúmulo de imagens é o problema mais provável de voltar a acontecer, porque ele piora gradualmente.

Manteria apenas as versões recentes e as que estão em uso. O `Azure Container Registry` oferece política de retenção automática, mas como ela depende do tier, a alternativa que funciona com o tier `Basic` provisionado aqui é um passo agendado na pipeline removendo as tags mais antigas.

## Cenário E: o Azure SQL começou a atingir 100% de DTU

### Como eu investigaria o consumo

#### Primeiro passo: identificar o que está consumindo

A métrica de `DTU` combina processamento, leitura e escrita em um único indicador. Verificaria qual desses componentes está no limite, porque cada um aponta para uma causa diferente.

#### Segundo passo: identificar as consultas mais custosas

Utilizaria o `Query Performance Insight`, que mostra as consultas com maior consumo de recursos no período.

Compararia com o comportamento anterior para responder a uma pergunta central: **isso começou agora ou vem crescendo gradualmente?**

* Se começou de repente, provavelmente coincide com um deploy ou com uma mudança de uso
* Se vem crescendo, provavelmente é o volume de dados aumentando sem que as consultas tenham sido ajustadas

### Possíveis soluções

Separo em duas categorias, porque elas resolvem problemas diferentes.

#### Soluções imediatas, para restabelecer o serviço

* **Aumentar o tier do banco**, por exemplo de `S1` para `S2`
  * A alteração de tier não exige recriar o banco, mas confirmaria na documentação qual é o impacto durante a operação
  * Resolve rapidamente, mas apenas adia o problema se a causa for uma consulta ineficiente
* **Verificar se há bloqueios entre transações**, que podem manter recursos ocupados sem que haja carga real

#### Soluções estruturais, para evitar a recorrência

* **Revisar índices**, que costuma ser a correção de maior impacto quando o problema está em consultas de leitura
* **Ajustar as consultas mais custosas** identificadas na análise
* **Aproveitar melhor o cache**, movendo para o `Redis` consultas repetidas de dados que mudam pouco
* **Revisar a origem da carga**, verificando se alguma rotina do Worker está executando com frequência maior que a necessária

### Relação com o Worker e o cache

A solução já possui `Redis` provisionado, então avaliar o que poderia ser cacheado seria uma das primeiras alternativas que eu consideraria antes de aumentar o tier do banco.

Vale também registrar uma particularidade do ambiente: o Worker escala automaticamente conforme a quantidade de mensagens na fila. Se ele estiver escalando bastante, **mais réplicas acessam o banco ao mesmo tempo**, o que pode ser a origem do consumo elevado.

Nesse caso, o problema não está no banco, mas no comportamento do Worker, e a solução seria limitar a quantidade de réplicas ou revisar o que cada uma executa. Este é um exemplo de por que considero importante investigar a causa antes de simplesmente aumentar o tier.

## Como a observabilidade apoia estes cenários

Os recursos definidos na parte de observabilidade foram escolhidos considerando situações como estas. A relação entre eles e os cenários é direta:

| Cenário | Recurso que ajudaria na investigação |
| ------- | ------------------------------------ |
| **A**: container não inicia | Logs do container no `Log Analytics` |
| **B**: API não acessa o `Redis` | Logs da API e mapa de dependências do `Application Insights` |
| **C**: escalando inesperadamente | Métricas de réplicas, requisições e profundidade da fila |
| **D**: falha no push da imagem | Log de execução da pipeline no `Azure DevOps` |
| **E**: `DTU` em 100% | Alerta de `DTU`, métricas do banco e `Query Performance Insight` |

Em quatro dos cinco cenários, a informação necessária **já estaria sendo coletada** antes do problema acontecer. Considero que esse é o principal valor de configurar observabilidade antecipadamente: no momento do incidente, o histórico já existe e não é preciso esperar o problema se repetir para começar a investigar.

## Observação final

Reconheço que a investigação real raramente segue uma sequência tão organizada quanto a descrita aqui. Na prática, algumas verificações acontecem em paralelo e a experiência com o ambiente costuma indicar atalhos.

O que procurei demonstrar é o raciocínio que eu seguiria: **partir da informação já disponível**, reduzir as possibilidades antes de alterar qualquer configuração e, sempre que possível, entender a causa antes de aplicar a correção.
