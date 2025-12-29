# MyColorForge Infrastructure

Repositório de Infrastructure as Code (IaC) para o projeto MyColorForge.

## Estrutura

```
mycolorforge-infra/
├── k8s/                          # Kubernetes manifests
│   ├── base/                     # Base configurations
│   │   ├── api-deployment.yaml   # Backend deployment
│   │   ├── frontend-deployment.yaml
│   │   ├── sonarqube/           # SonarQube stack
│   │   ├── observability/       # Monitoring (Tempo, Loki, Grafana)
│   │   └── ...
│   └── overlays/                # Kustomize overlays
│       ├── staging/
│       └── production/
├── tekton/                      # CI/CD Pipelines
│   ├── pipelines/               # Pipeline definitions
│   ├── tasks/                   # Reusable tasks
│   ├── triggers/                # GitHub webhooks
│   ├── rbac/                    # Service accounts & permissions
│   └── cache/                   # PVCs for caching
├── argocd/                      # GitOps configurations
│   └── applications/
├── docs/                        # Documentation
│   └── architecture/
│       └── DEVSECOPS.md        # Security architecture
└── scripts/                     # Setup scripts
    └── setup/
```

## Quick Start

### Pré-requisitos

- Kubernetes cluster (1.28+)
- kubectl configurado
- Tekton Pipelines instalado
- ArgoCD instalado

### Deploy

```bash
# Aplicar Tekton tasks
kubectl apply -f tekton/tasks/

# Aplicar pipelines
kubectl apply -f tekton/pipelines/

# Aplicar triggers
kubectl apply -f tekton/triggers/

# Deploy SonarQube
kubectl apply -k k8s/base/sonarqube/
```

## CI/CD Pipeline

### Backend (Go API)

```
Clone → Gitleaks → Test → SonarQube ──┬──→ Trivy → Update Manifests
                    │                 │
                    └→ OWASP ─────────┘
                    │                 │
                    └→ Build Image ───┘
```

### Frontend (Next.js)

```
Clone → Gitleaks → Build → SonarQube ──┬──→ Trivy → Update Manifests
                     │                 │
                     └→ npm audit ─────┘
                     │                 │
                     └→ Build Image ───┘
```

## DevSecOps

Este projeto implementa práticas DevSecOps com as seguintes ferramentas:

| Controle | Ferramenta | Fase |
|----------|------------|------|
| Secret Scanning | Gitleaks | Pre-commit/CI |
| SAST | SonarQube | Build |
| SCA | OWASP/govulncheck | Build |
| Container Scan | Trivy | Package |
| Image Signing | Cosign | Package |
| SBOM | Syft | Package |

Documentação completa: [docs/architecture/DEVSECOPS.md](docs/architecture/DEVSECOPS.md)

## Ambientes

| Ambiente | Namespace | URL |
|----------|-----------|-----|
| Staging | colorforge | https://colorforge.local |
| Production | colorforge-prod | https://mycolorforge.com |

## Secrets

Os seguintes secrets devem ser criados manualmente:

```bash
# Harbor registry credentials
kubectl create secret docker-registry harbor-registry-credentials \
  -n tekton-pipelines \
  --docker-server=harbor.local \
  --docker-username=admin \
  --docker-password=<password>

# GitHub credentials
kubectl create secret generic github-credentials \
  -n tekton-pipelines \
  --from-literal=username=<username> \
  --from-literal=password=<token>

# SonarQube token
kubectl create secret generic sonarqube-token \
  -n tekton-pipelines \
  --from-literal=SONAR_TOKEN=<token> \
  --from-literal=SONAR_HOST_URL=http://sonarqube.sonarqube.svc.cluster.local:9000
```

## Monitoramento

- **Grafana:** https://grafana.local
- **ArgoCD:** https://argocd.local
- **Tekton Dashboard:** https://tekton.local
- **SonarQube:** https://sonar.local
- **Harbor:** https://harbor.local

## Contribuindo

1. Alterações em `k8s/` são sincronizadas automaticamente via ArgoCD
2. Alterações em `tekton/` requerem `kubectl apply` manual
3. Documente mudanças arquiteturais em `docs/`

## Licença

Proprietário - MyColorForge
