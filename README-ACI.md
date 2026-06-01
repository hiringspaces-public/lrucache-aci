# HiringSpaces — LRU Cache Interview Environment

Browser-based VS Code (code-server) with Java 21 + .NET 8, served from Azure Container Instances. Cold-start target: **< 60 seconds**.

---

## Architecture

```
GitHub repo (lrucache)
        │
        ▼  (on push to main)
GitHub Actions ──► Azure Container Registry (ACR)
                           │
                           │  (backend API call: POST /sessions)
                           ▼
                  Azure Container Instances (1 per candidate)
                           │
                           ▼
                  code-server :8080  ← candidate browser
```

---

## Files in this folder

| File | Purpose |
|---|---|
| `Dockerfile` | Main image — code-server + Java 21 + .NET 8 + pre-cloned repo |
| `config.yaml` | code-server config (auth mode, port) |
| `workspace.code-workspace` | VS Code workspace with tasks, settings, extensions |
| `scripts/start.sh` | Container entrypoint — git pull, pre-build, start code-server |
| `build-push-acr.sh` | One-shot manual build + ACR push |
| `provision-session.sh` | Called by backend to spin up one ACI per interview |
| `teardown-session.sh` | Called by backend on session end to delete ACI |
| `.github-workflow-build-acr.yml` | Copy to `.github/workflows/build-acr.yml` in the repo |

---

## One-time Setup

### 1. Azure resources

```bash
# Resource group
az group create --name hiringspaces-rg --location eastus

# Container Registry (Premium for geo-replication; Standard is fine for MVP)
az acr create \
  --resource-group hiringspaces-rg \
  --name hiringspacesacr \
  --sku Standard \
  --admin-enabled true
```

### 2. Build & push the image

```bash
export ACR_NAME=hiringspacesacr
export RESOURCE_GROUP=hiringspaces-rg

chmod +x build-push-acr.sh provision-session.sh teardown-session.sh scripts/start.sh
./build-push-acr.sh
```

First build ~10–15 min (installs Java, .NET, pre-restores deps).  
Subsequent builds hit Docker layer cache — typically 2–4 min.

### 3. GitHub Actions secrets

Add these in the repo's **Settings → Secrets → Actions**:

| Secret | Value |
|---|---|
| `ACR_NAME` | `hiringspacesacr` |
| `ACR_USERNAME` | output of `az acr credential show -n hiringspacesacr --query username -o tsv` |
| `ACR_PASSWORD` | output of `az acr credential show -n hiringspacesacr --query "passwords[0].value" -o tsv` |
| `RESOURCE_GROUP` | `hiringspaces-rg` |

Copy `.github-workflow-build-acr.yml` → `.github/workflows/build-acr.yml` in the repo.

---

## Backend Integration

Your backend calls `provision-session.sh` (or replicates its Azure CLI calls via the Azure SDK):

```bash
RESULT=$(./provision-session.sh \
  --candidate-id "cand_abc123" \
  --session-token "$(openssl rand -hex 32)")

URL=$(echo "$RESULT" | jq -r .url)
# → http://hs-cand-abc123.eastus.azurecontainer.io:8080
```

### REST API example (Python / Azure SDK)

```python
import subprocess, json, secrets

def start_interview_env(candidate_id: str) -> dict:
    token = secrets.token_hex(32)
    result = subprocess.run(
        ["./provision-session.sh",
         "--candidate-id", candidate_id,
         "--session-token", token],
        capture_output=True, text=True, check=True
    )
    return json.loads(result.stdout)

def end_interview_env(container_name: str):
    subprocess.run(
        ["./teardown-session.sh", "--container-name", container_name],
        check=True
    )
```

### Environment variables injected per session

| Variable | Description |
|---|---|
| `CANDIDATE_ID` | Passed to the container; logged at startup |
| `SESSION_TOKEN` | If set, becomes the code-server password (token-based auth) |

---

## Startup Timeline (target < 60 s)

| Step | Where | Time |
|---|---|---|
| ACI container pull from ACR | Azure infra | ~15–25 s (image ~2 GB compressed) |
| Container starts, git pull | `start.sh` | ~3–5 s |
| code-server ready on :8080 | `start.sh` | ~5–8 s |
| Java/C# extensions activate | VS Code | background, ~10–20 s |
| **Total to usable VS Code** | | **< 60 s** |

The pre-restored Maven/NuGet caches baked into the image mean the first `mvn test` / `dotnet test` runs in seconds, not minutes.

---

## Candidate Experience

1. Interviewer clicks **Start Session** in HiringSpaces dashboard.
2. Backend calls `provision-session.sh`, gets back a URL.
3. Dashboard shows a **"Open Environment"** button linking to that URL.
4. Candidate opens the URL — sees VS Code in the browser with the LRU Cache repo already open.
5. Available immediately: Java project, C# solution, draw.io diagram, integrated terminal.
6. At session end, interviewer clicks **End Session** → `teardown-session.sh` deletes the ACI.

---

## Cost

ACI billing is per second of CPU + memory usage.  
A 2 vCPU / 4 GB instance in East US costs ~**$0.003/min** = ~$0.18 for a 60-minute interview.

---

## Scaling Notes

- Each interview is **one ACI container** — completely isolated.
- No shared state between candidates.
- ACR `latest` tag always points to the most recent passing build.
- To support multiple problem sets, build separate images and pick by `IMAGE_TAG` in the provision call.


# 1. Create a service principal
az ad sp create-for-rbac --name "hiringspaces-github-actions" --skip-assignment

# 2. Note the appId (CLIENT_ID) and tenant (TENANT_ID) from output
# 3. Get your subscription ID
az account show --query id -o tsv

# 4. Assign AcrPush role (scoped to the registry only — least privilege)
az role assignment create \
  --assignee <appId> \
  --role AcrPush \
  --scope $(az acr show -n hiringspacesacr --query id -o tsv)

# 5. Add federated credential so GitHub can authenticate
contact [ ~ ]$ az ad app federated-credential create \
  --id e31b2e4e-e8fb-4dca-a54d-125db305b545 \
  --parameters '{
    "name": "github-actions",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:hiringspaces-public/lrucache-aci:ref:refs/heads/main",
    "audiences": ["api://AzureADTokenExchange"]
  }'

{
  "@odata.context": "https://graph.microsoft.com/v1.0/$metadata#applications('b8c57547-24c7-43e1-9a83-aef6cd92a073')/federatedIdentityCredentials/$entity",
  "audiences": [
    "api://AzureADTokenExchange"
  ],
  "description": null,
  "id": "ba888060-eeb7-4d75-bcb5-6af14a5b6713",
  "issuer": "https://token.actions.githubusercontent.com",
  "name": "github-actions",
  "subject": "repo:hiringspaces-public/lrucache-aci:ref:refs/heads/main"
}

          client-id: e31b2e4e-e8fb-4dca-a54d-125db305b545 
          tenant-id: 65d86ba7-383e-47c3-b628-1269775512dd
          subscription-id: c674247f-9138-4470-9583-4f10b8076c8f


 run: |
          TOKEN=$(az acr get-login-password --subscription c674247f-9138-4470-9583-4f10b8076c8f)
          echo "$TOKEN" | docker login hiringspacesacr-bdandkgvhgaghjeg.azurecr.io \
            --username 00000000-0000-0000-0000-000000000000 \
            --password-stdin


    az role assignment create \
  --assignee <CLIENT_ID> \
  --role Reader \
  --scope "$ACR_ID"

  needed acrpush and reader permission

creating subscription CI
az provider register --namespace Microsoft.ContainerInstance --subscription c674247f-9138-4470-9583-4f10b8076c8f

create MI
az identity create --name hs-aci-identity --resource-group Hiringspaces

az role assignment create \
  --assignee e20aca50-2f65-466a-b28f-9dfd6cd5db1a \
  --role AcrPull \
  --scope $(az acr show -n hiringspacesacr --query id -o tsv)

az role assignment create \
  --assignee e20aca50-2f65-466a-b28f-9dfd6cd5db1a \
  --role Reader \
  --scope $(az acr show -n hiringspacesacr --query id -o tsv)