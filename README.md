### Experimenting with `devcontainer`

Install `devcontainer`:
```
brew install devcontainer
```

1. Open `zsh` inside the container:
```
cd ~/git/h0tbird/meshlab
devcontainer up --dotfiles-repository https://github.com/h0tbird/devcontainer.git --workspace-folder .
devcontainer exec --workspace-folder . zsh
```

2. Create the lab:
```
./bin/meshlab-kind create
```

3. Monitor progress in a separate terminal:
```
devcontainer exec --workspace-folder . zsh
watch "k --context kind-kube-00 get po -A; echo; k --context kind-pasta-1 get po -A; echo; k --context kind-pasta-2 get po -A"
```

4. Delete the lab:
```
./bin/meshlab-kind delete
```