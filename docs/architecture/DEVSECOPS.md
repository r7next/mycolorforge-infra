# Arquitetura DevSecOps - MyColorForge

## Visão Geral

Este documento descreve a arquitetura de segurança integrada ao pipeline CI/CD do MyColorForge, seguindo as melhores práticas de DevSecOps.

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                              PIPELINE DEVSECOPS                                      │
├─────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                      │
│  ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐           │
│  │  Code   │───▶│  Build  │───▶│  Test   │───▶│ Package │───▶│ Deploy  │           │
│  │  Commit │    │         │    │         │    │         │    │         │           │
│  └────┬────┘    └────┬────┘    └────┬────┘    └────┬────┘    └────┬────┘           │
│       │              │              │              │              │                 │
│       ▼              ▼              ▼              ▼              ▼                 │
│  ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐           │
│  │Gitleaks │    │SonarQube│    │  OWASP  │    │  Trivy  │    │ ArgoCD  │           │
│  │ Secrets │    │  SAST   │    │   SCA   │    │Container│    │ GitOps  │           │
│  └─────────┘    └─────────┘    └─────────┘    └─────────┘    └─────────┘           │
│                                                     │                               │
│                                                     ▼                               │
│                                              ┌─────────────┐                        │
│                                              │   Cosign    │                        │
│                                              │  Signing +  │                        │
│                                              │  Syft SBOM  │                        │
│                                              └─────────────┘                        │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

## Ferramentas de Segurança

### 1. Gitleaks - Secret Scanning

**Propósito:** Detectar credenciais, API keys, tokens e outros segredos hardcoded no código fonte.

**Fase:** Pre-commit / CI

**Configuração:**
```yaml
taskRef:
  name: gitleaks-scan
params:
  - name: fail-on-leak
    value: "true"
  - name: redact
    value: "true"
```

**O que detecta:**
- API Keys (AWS, GCP, Azure, GitHub, etc.)
- Tokens de acesso
- Senhas hardcoded
- Chaves privadas
- Connection strings

**Ação em caso de falha:** Pipeline bloqueado até remoção do secret.

---

### 2. SonarQube - Static Application Security Testing (SAST)

**Propósito:** Análise estática de código para identificar vulnerabilidades, code smells e bugs.

**Fase:** Build

**Configuração:**
```yaml
taskRef:
  name: sonarqube-scan
params:
  - name: quality-gate-wait
    value: "true"
```

**O que analisa:**
- Vulnerabilidades de segurança (SQL Injection, XSS, etc.)
- Code smells
- Bugs potenciais
- Cobertura de testes
- Duplicação de código
- Complexidade ciclomática

**Quality Gate:**
- Cobertura mínima: Configurável
- Novos bugs: 0
- Novas vulnerabilidades: 0
- Security Hotspots revisados: 100%

**Acesso:** https://sonar.local ou https://sonar.mycolorforge.com

---

### 3. OWASP Dependency Check - Software Composition Analysis (SCA)

**Propósito:** Identificar vulnerabilidades conhecidas (CVEs) em dependências de terceiros.

**Fase:** Build

**Configuração:**
```yaml
taskRef:
  name: owasp-dependency-check
params:
  - name: project-type
    value: "go"  # ou "nodejs"
  - name: fail-on-cvss
    value: "7"   # CVSS >= 7 falha o build
```

**Ferramentas por linguagem:**
| Linguagem | Ferramenta | Database |
|-----------|------------|----------|
| Go | govulncheck | Go Vulnerability Database |
| Node.js | npm audit | npm Advisory Database |

**Severidade CVSS:**
- 0.0 - 3.9: Low
- 4.0 - 6.9: Medium
- 7.0 - 8.9: High
- 9.0 - 10.0: Critical

**Ação:** Pipeline falha em CVSS >= threshold configurado.

---

### 4. Trivy - Container Security Scanning

**Propósito:** Scan de vulnerabilidades em imagens de container.

**Fase:** Package (após build da imagem)

**Configuração:**
```yaml
taskRef:
  name: trivy-scan
params:
  - name: severity
    value: "HIGH,CRITICAL"
  - name: exit-code
    value: "0"  # 0 = warn only, 1 = fail
```

**O que escaneia:**
- Vulnerabilidades do SO base (Alpine, Debian, etc.)
- Vulnerabilidades em pacotes de linguagem
- Secrets em layers da imagem
- Misconfigurations

**Relatório:**
- Formato: Table, JSON, SARIF
- Armazenado no workspace do pipeline

**Cache:** PVC persistente para database de vulnerabilidades.

---

### 5. Cosign - Image Signing

**Propósito:** Assinatura criptográfica de imagens para garantir integridade e autenticidade.

**Fase:** Package (após scan bem-sucedido)

**Modos de operação:**
1. **Keyless (Sigstore/Fulcio):** Usa identidade OIDC
2. **Key-based:** Usa par de chaves RSA/ECDSA

**Configuração:**
```yaml
taskRef:
  name: cosign-sign
params:
  - name: signature-type
    value: "keyless"
```

**Verificação:**
```bash
cosign verify harbor.local/colorforge/backend:v1.0.0
```

---

### 6. Syft - SBOM Generation

**Propósito:** Gerar Software Bill of Materials listando todos componentes da aplicação.

**Fase:** Package

**Formatos suportados:**
- CycloneDX (JSON/XML)
- SPDX (JSON/Tag-Value)
- Syft JSON

**Configuração:**
```yaml
taskRef:
  name: syft-sbom
params:
  - name: output-format
    value: "cyclonedx-json"
```

**Uso do SBOM:**
- Compliance (regulatório)
- Rastreabilidade de componentes
- Análise de licenças
- Resposta a incidentes (Ex: Log4Shell)

---

## Fluxo do Pipeline

### Backend (Go API)

```
Clone → Gitleaks → Test → SonarQube ──┬──→ Trivy → Cosign → SBOM → GitOps
                    │                 │
                    └→ OWASP ─────────┘
                    │                 │
                    └→ Build Image ───┘
```

### Frontend (Next.js)

```
Clone → Gitleaks → Build → SonarQube ──┬──→ Trivy → Cosign → SBOM → GitOps
                     │                 │
                     └→ npm audit ─────┘
                     │                 │
                     └→ Build Image ───┘
```

---

## Matriz de Controles OWASP Top 10

| OWASP Top 10 2021 | Controle | Ferramenta |
|-------------------|----------|------------|
| A01 - Broken Access Control | SAST | SonarQube |
| A02 - Cryptographic Failures | SAST, Secret Scan | SonarQube, Gitleaks |
| A03 - Injection | SAST | SonarQube |
| A04 - Insecure Design | Code Review | SonarQube (Quality Gate) |
| A05 - Security Misconfiguration | Container Scan | Trivy |
| A06 - Vulnerable Components | SCA | OWASP/govulncheck, Trivy |
| A07 - Auth Failures | SAST | SonarQube |
| A08 - Data Integrity Failures | Image Signing | Cosign |
| A09 - Security Logging | Runtime | Faro/OpenTelemetry |
| A10 - SSRF | SAST | SonarQube |

---

## Configuração de Quality Gates

### SonarQube Quality Gate

| Métrica | Condição | Threshold |
|---------|----------|-----------|
| Coverage | >= | 80% |
| Duplicated Lines | <= | 3% |
| Maintainability Rating | <= | A |
| Reliability Rating | <= | A |
| Security Rating | <= | A |
| Security Hotspots Reviewed | >= | 100% |
| New Bugs | = | 0 |
| New Vulnerabilities | = | 0 |
| New Code Smells | <= | 10 |

### Trivy Severity Threshold

| Ambiente | Threshold | Ação |
|----------|-----------|------|
| Development | CRITICAL | Warn |
| Staging | HIGH, CRITICAL | Warn |
| Production | HIGH, CRITICAL | Block |

### OWASP CVSS Threshold

| Ambiente | CVSS Score | Ação |
|----------|------------|------|
| Development | >= 9.0 | Block |
| Staging | >= 7.0 | Block |
| Production | >= 4.0 | Block |

---

## Secrets Management

### Secrets no Kubernetes

```yaml
# Sealed Secrets para valores sensíveis
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: app-secrets
spec:
  encryptedData:
    DATABASE_URL: AgBy8h...
    JWT_SECRET: AgCtr9...
```

### Secrets no Pipeline

| Secret | Namespace | Uso |
|--------|-----------|-----|
| harbor-registry-credentials | tekton-pipelines | Push de imagens |
| github-credentials | tekton-pipelines | Clone de repos |
| sonarqube-token | tekton-pipelines | Análise SonarQube |
| cosign-key | tekton-pipelines | Assinatura de imagens |

---

## Monitoramento e Alertas

### Métricas de Segurança

- Vulnerabilidades por severidade
- Taxa de falha de Quality Gate
- Tempo médio de remediação
- Secrets detectados por período

### Integração com Observabilidade

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Faro      │────▶│   Tempo     │────▶│   Grafana   │
│  (Frontend) │     │             │     │ Dashboards  │
└─────────────┘     └─────────────┘     └─────────────┘
                           │
                           ▼
                    ┌─────────────┐
                    │   Loki      │
                    │   (Logs)    │
                    └─────────────┘
```

---

## Compliance e Auditoria

### SBOM para Compliance

O SBOM gerado pelo Syft atende:
- **NTIA Minimum Elements** para SBOMs
- **Executive Order 14028** (US)
- **CRA** (EU Cyber Resilience Act)

### Retenção de Artefatos

| Artefato | Retenção | Local |
|----------|----------|-------|
| SBOM | 2 anos | Harbor / S3 |
| Scan Reports | 1 ano | MinIO |
| Audit Logs | 7 anos | Loki |
| Assinaturas | Permanente | Sigstore/Rekor |

---

## Resposta a Incidentes

### Processo de CVE

1. **Detecção:** Trivy/OWASP detecta CVE
2. **Notificação:** Alert via Slack/Email
3. **Avaliação:** Análise de impacto
4. **Remediação:** Update de dependência
5. **Verificação:** Re-scan
6. **Deploy:** GitOps atualiza ambiente

### Rollback de Segurança

```bash
# Verificar assinatura antes de rollback
cosign verify harbor.local/colorforge/backend:previous-tag

# ArgoCD rollback
argocd app rollback colorforge-backend
```

---

## Roadmap de Segurança

### Implementado ✅
- [x] SonarQube (SAST)
- [x] Trivy (Container Scan)
- [x] OWASP Dependency Check (SCA)
- [x] Gitleaks (Secret Scan)
- [x] Cosign (Image Signing)
- [x] Syft (SBOM)

### Planejado 📋
- [ ] DAST com OWASP ZAP
- [ ] Runtime Security com Falco
- [ ] Network Policies
- [ ] Pod Security Standards
- [ ] OPA/Gatekeeper Policies

---

## Referências

- [OWASP Top 10](https://owasp.org/Top10/)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
- [NIST Cybersecurity Framework](https://www.nist.gov/cyberframework)
- [Sigstore Documentation](https://docs.sigstore.dev/)
- [SonarQube Security Rules](https://rules.sonarsource.com/)
