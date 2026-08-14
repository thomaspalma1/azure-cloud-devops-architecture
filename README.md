### Azure Cloud DevOps Architecture

<p align="justify">
   <img src="https://cdn.jsdelivr.net/gh/devicons/devicon@latest/icons/azure/azure-original.svg" width="50" height="50"/>
</p>


## Navegação

| Diretório | Conteúdo |
|---|---|
| 🏛️ [**Architecture**](./architecture) | Recursos **Azure**, comunicação entre eles, `justificativas técnicas` e redução de custos |
| 📐 [**Diagrams**](./diagrams) | Diagramas da solução em `Draw.io` e `SVG` |
| 📊 [**Sizing**](./sizing) | `SKUs`, justificativa técnica, `custo mensal estimado` e `escalabilidade automática` |
| 🐳 [**Docker**](./docker) | `Dockerfiles`, `multi-stage build`, redução de imagens e `boas práticas de segurança` |
| 🌿 [**Branching**](./branching) | Estratégia de `branches`, `Pull Requests`, `policies` e versionamento |
| 🔄 [**Pipelines**](./pipelines) | Pipelines `CI/CD` em `Azure Pipelines YAML`, `smoke test` e `rollback` |
| 🏗️ [**Infrastructure**](./infrastructure) | `Infraestrutura como Código (IaC)` com `Terraform`, módulos e ambientes |
| 🔐 [**Security**](./security) | `Key Vault`, `Managed Identity`, `RBAC` e `Microsoft Entra ID` |
| 📈 [**Observability**](./observability) | `Logs centralizados`, métricas, dashboards, alertas e `distributed tracing` |
| 🤖 [**Ai-integration**](./ai-integration) | `Azure AI Foundry`, gestão de `prompts`, consumo e `controle de custos` |
| 🔧 [**Troubleshooting**](./troubleshooting) | Investigação e resolução dos `cenários propostos` |


```
docker
├── api
│   ├── Dockerfile
│   └── README.md
├── docker
│   └── web
│       └── docker-entrypoint.d
├── README.md
├── web
│   ├── Dockerfile
│   └── README.md
└── worker
    ├── Dockerfile
    └── README.md
```