## `worker/Dockerfile`

**Finalidade:** empacota o Background Worker em .NET, responsável pelo processamento assíncrono. No fluxo da solução, a API publica mensagens em uma Storage Queue e o Worker as consome  desacoplando operações demoradas (processamento de arquivos enviados, chamadas ao Azure OpenAI, geração de relatórios) do ciclo de requisição/resposta HTTP.

No ambiente provisionado, esta imagem roda como Container App **sem ingress**, escalando por profundidade de fila via KEDA.

### Duas diferenças deliberadas em relação à API

Os dois Dockerfiles são propositalmente parecidos nos estágios de restore e publish  são projetos .NET com o mesmo ciclo de build. As diferenças estão no estágio final, e ambas decorrem do mesmo fato: **o Worker não expõe HTTP**.

#### 1. Imagem base `runtime` em vez de `aspnet`

| Componente | Imagem final                         | Contém                                |
| ---------- | ------------------------------------ | ------------------------------------- |
| API        | `dotnet/aspnet:10.0-noble-chiseled`  | Runtime .NET + ASP.NET Core Framework |
| Worker     | `dotnet/runtime:10.0-noble-chiseled` | Apenas o runtime .NET                 |

O ASP.NET Core Framework existe para servir HTTP: Kestrel, middleware pipeline, roteamento, model binding. Um Worker que apenas consome fila não usa nada disso. Herdar de `aspnet` carregaria cerca de **20 MB** de framework que nunca seria executado e, do ponto de vista de segurança, código não utilizado ainda é superfície de ataque.

A imagem final fica em torno de **90 MB**, contra ~110 MB da API.

> Este é o tipo de decisão que evidencia que os Dockerfiles foram pensados por componente, e não copiados entre si. Um `docker/worker/Dockerfile` idêntico ao da API funcionaria, só seria maior e menos justificável.

#### 2. Ausência de `EXPOSE` e de `ASPNETCORE_HTTP_PORTS`

A API declara `EXPOSE 8080` e define a porta do Kestrel. O Worker não declara porta alguma, porque não escuta em nenhuma.

Isso tem reflexo direto no provisionamento: no Container Apps, o Worker é criado **sem configuração de ingress**. Declarar uma porta que o processo não escuta criaria uma inconsistência entre a imagem e a infraestrutura  e, pior, poderia levar alguém a configurar um health probe HTTP que nunca responderia.

### Como o Worker é monitorado sem endpoint HTTP

Como não há endpoint para um probe HTTP consultar, a saúde do Worker é observada por outros sinais:

| Sinal                   | Origem                                                                                                                                         |
| ----------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| Processo vivo           | O Container Apps reinicia a réplica se o processo terminar (o `ENTRYPOINT` em forma *exec* garante que o .NET seja o PID 1 e receba os sinais) |
| Profundidade da fila    | Métrica da Storage Queue no Azure Monitor — fila crescendo sem consumo indica Worker travado, mesmo com o processo vivo                        |
| Telemetria da aplicação | Application Insights recebe traces e exceções emitidos pelo próprio Worker                                                                     |

O detalhamento das regras de alerta está em [`observability/`](../observability/README.md).

### Estrutura em três estágios

Idêntica à da API  os motivos de cada decisão (ordenação por frequência de mudança, `--no-restore`, `--self-contained false`, `PublishReadyToRun`, `USER $APP_UID`, forma *exec* do `ENTRYPOINT`) estão explicados na seção [`api/Dockerfile`](#apidockerfile) e não se repetem aqui.

Uma observação sobre `PublishReadyToRun` neste componente especificamente: o ganho de startup é ainda mais relevante para o Worker do que para a API. Com autoscaling por profundidade de fila e `min_replicas = 0`, ele passa a maior parte do tempo desligado e só sobe quando há mensagens acumuladas  cada ciclo de trabalho começa com uma inicialização.

### Como buildar

```bash
docker build -f docker/worker/Dockerfile \
  --build-arg VERSION=1.0.0 \
  -t acracdahomolog.azurecr.io/worker:1.0.0 .
```

Assim como na API, o build context é a **raiz do repositório `worker`**.
