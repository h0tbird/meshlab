
## Getting Started

<details><summary><b>Option A</b>: Local Development (VS Code)</summary>
<p>

1. Open the repository in **VS Code**.
2. Make sure the **Dev Containers** extension is installed.
3. When prompted, click **“Reopen in Container”**.
   - If the prompt doesn’t appear, open the Command Palette and run:
     ```console
     Dev Containers: Reopen in Container
     ```
</p>
</details>

<details><summary><b>Option B</b>: Local Development (CLI)</summary>
<p>

1. TODO: To be documented.
</p>
</details>

<details><summary><b>Option C</b>: GitHub Codespaces (VS Code)</summary>
<p>

1. In the GitHub WebUI, go to **Code → Codespaces**.
2. Click **“Create codespace on master”**.
</p>
</details>

<details><summary><b>Option D</b>: GitHub Codespaces (CLI)</summary>
<p>

1. Start a codespace using `gh`
```console
unset GITHUB_TOKEN
gh config set pager cat
gh auth refresh -h github.com -s codespace
gh cs create -R h0tbird/meshlab -m largePremiumLinux -d playground
CODESPACE=$(gh cs list --json name --jq '.[].name' | grep -m1 '^playground')
gh cs ssh -c ${CODESPACE}
```

2. Forward the ports
```console
gh cs ports forward \
8080:8080 \
8081:8081 \
8082:8082 \
8083:8083 \
8084:8084 \
8085:8085 \
-c ${CODESPACE}
```
</p>
</details>

---

## Usage

Start the lab by running the following command in a terminal:
```console
meshlab create
```

Optionally, you can monitor the status from another terminal by running:
```console
meshlab watch
```

As the lab starts up, the following services will become available:

- **Argo CD:** http://127.0.0.1:8080
- **Argo Workflows:** http://127.0.0.1:8081
- **Vault:** http://127.0.0.1:8082
- **Prometheus:** http://127.0.0.1:8083
- **Grafana:** http://127.0.0.1:8084
- **Kiali:** http://127.0.0.1:8085
- **Tilt pasta-1:** http://127.0.0.1:9091
- **Tilt pasta-2:** http://127.0.0.1:9092

Use `admin` + `meshlab123` as credentials when prompted.

---

## Make targets

In addition to the lab deployed via `meshlab create`, this repository includes a few `make` targets to help with Istio development:

```console
$ make help

Usage:
  make <target>
  help             Display this help.

Development Targets
  toolbox          Build toolbox image.
  istio-binaries   Build Istio binaries.
  istio-images     Build Istio images.
  istio-charts     Build Istio charts.
  istio-labels     Add labels to Istio images.
```

---

## Design Notes

- VS Code Dev Containers copies `~/.gitconfig` into the container.
- Host SSH agent available at `/ssh-agent`.
- Docker sockets: DinD at `/var/run/docker.sock`, DooD at `/var/run/docker-host.sock` (default).
- Kind uses DooD; Istio `build-tools` uses DinD.
- Istio sources are cloned to `../istio` if missing. Both repos mount under `/workspaces`.
- Each workload cluster's Tilt watches `pilot-discovery` and live-updates on change.
- Run `make istio-binaries` to build new Istio binaries.
