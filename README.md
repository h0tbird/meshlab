## GitHub CLI Codespaces
```console
unset GITHUB_TOKEN
gh auth refresh -h github.com -s codespace
gh cs create -R h0tbird/meshlab -m largePremiumLinux -d playground
gh cs ssh
meshlab create
```
