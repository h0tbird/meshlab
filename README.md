
## Getting Started

### Option A: Local Development (Dev Containers)

1. Open the repository in **VS Code**.
2. Make sure the **Dev Containers** extension is installed.
3. When prompted, click **“Reopen in Container”**.
   - If the prompt doesn’t appear, open the Command Palette and run:
     ```
     Dev Containers: Reopen in Container
     ```

### Option B: GitHub Codespaces

1. In the GitHub web UI, go to **Code → Codespaces**.
2. Click **“Create codespace on master”**.


**Option B**: In the Github webUI go to Code --> Codespaces and click on “**Create codespace on master**”. Run `meshlab create` in the terminal.

### Start a codespace using `gh`
```console
unset GITHUB_TOKEN
gh config set pager cat
gh auth refresh -h github.com -s codespace
gh cs create -R h0tbird/meshlab -m largePremiumLinux -d playground
CODESPACE=$(gh cs list --json name --jq '.[].name' | grep -m1 '^playground')
gh cs ssh -c ${CODESPACE}
```

### Bring up meshlab
```console
meshlab create
```

### Forward the ports
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