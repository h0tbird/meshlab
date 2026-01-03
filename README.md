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
```
meshlab create
```

### Forward the ports
```
gh cs ports forward \
8080:8080 \
8081:8081 \
8082:8082 \
8083:8083 \
8084:8084 \
8085:8085 \
-c ${CODESPACE}
```