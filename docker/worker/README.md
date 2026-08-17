# Docker - Worker

## `worker/Dockerfile`

**Finalidade:** empacota o Background Worker em .NET, responsável pelo processamento assíncrono. No fluxo da solução, a API publica mensagens em uma Storage Queue e o Worker as consome, desacoplando operações demoradas (processamento de arquivos enviados, chamadas ao Azure OpenAI, geração de relatórios) do ciclo de requisição/resposta HTTP.

No ambiente provisionado, esta imagem roda como Container App **sem ingress**, escalando por profundidade de fila via KEDA.

### Duas diferenças deliberadas em relação à API

Os dois Dockerfiles são propositalmente parecidos nos estágios de restore e publish, são projetos .NET com o mesmo ciclo de build. As diferenças estão no estágio final, e ambas decorrem do mesmo fato: **o Worker não expõe HTTP**.

#### 1. Imagem base `runtime` em vez de `aspnet`

| Componente | Imagem final                         | Contém                                |
| ---------- | ------------------------------------ | ------------------------------------- |
| API        | `dotnet/aspnet:10.0-noble-chiseled`  | Runtime .NET + ASP.NET Core Framework |
| Worker     | `dotnet/runtime:10.0-noble-chiseled` | Apenas o runtime .NET                 |

O ASP.NET Core Framework existe para servir HTTP: Kestrel, middleware pipeline, roteamento, model binding. Um Worker que apenas consome fila não usa nada disso. Herdar de `aspnet` carregaria alguns MB de framework que nunca seria executado e, do ponto de vista de segurança, código não utilizado ainda é superfície de ataque.

A imagem final fica menor que a da API pela mesma diferença.

#### 2. Ausência de `EXPOSE` e de `ASPNETCORE_HTTP_PORTS`

A API declara `EXPOSE 8080` e define a porta do Kestrel. O Worker não declara porta alguma, porque não escuta em nenhuma.

Isso tem reflexo direto no provisionamento: no Container Apps, o Worker é criado **sem configuração de ingress**. Declarar uma porta que o processo não escuta criaria uma inconsistência entre a imagem e a infraestrutura e, pior, poderia levar alguém a configurar um health probe HTTP que nunca responderia.

### Como o Worker é monitorado sem endpoint HTTP

O módulo Terraform só cria os probes quando o componente tem ingress, então o Worker não tem probe algum. Sua saúde é observada por outros sinais:

| Sinal                   | Origem                                                                                                                                         |
| ----------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| Processo vivo           | O Container Apps reinicia a réplica se o processo terminar (o `ENTRYPOINT` em forma *exec* garante que o .NET seja o PID 1 e receba os sinais) |
| Profundidade da fila    | Métrica da Storage Queue no Azure Monitor, fila crescendo sem consumo indica Worker travado, mesmo com o processo vivo                         |
| Telemetria da aplicação | Application Insights recebe traces e exceções emitidos pelo próprio Worker                                                                     |

Na pipeline, o smoke test correspondente também é diferente: em vez de consultar `/healthz`, o `smoke-test-worker.sh` verifica se a nova revisão ficou em estado `Running`.

O detalhamento das regras de alerta está em [`observability/`](../../observability/README.md).

### Estrutura em três estágios

Idêntica à da API. Os motivos de cada decisão (ordenação por frequência de mudança, `--no-restore`, `--self-contained false`, `PublishReadyToRun`, `USER $APP_UID`, forma *exec* do `ENTRYPOINT`) estão explicados em [`api/`](../api/README.md#decisões-linha-a-linha) e não se repetem aqui, inclusive a premissa sobre copiar um único `.csproj` no estágio de restore.

O `PublishReadyToRun` vale ainda mais aqui do que na API: com escala por profundidade de fila e `min_replicas = 0`, o Worker fica desligado a maior parte do tempo e sobe sempre que há mensagens acumuladas, então cada ciclo de trabalho começa com uma inicialização.

### Como buildar

```bash
docker build -f docker/worker/Dockerfile \
  --build-arg VERSION=1.0.0 \
  -t acracdahomolog.azurecr.io/worker:1.0.0 .
```

Assim como na API, o build context é a **raiz do repositório `worker`**, e a pipeline passa a versão da aplicação por `--build-arg VERSION`.

## `worker/.dockerignore`

Idêntico ao [`.dockerignore` da API](../api/README.md#apidockerignore), e pelo mesmo motivo: os dois são soluções .NET com a mesma estrutura de projeto, os mesmos artefatos locais (`bin/`, `obj/`) e os mesmos arquivos de configuração sensíveis (`appsettings.Development.json`, `secrets.json`, certificados). Que os dois arquivos sejam iguais é o resultado esperado, e cada um vive no repositório da sua aplicação.
