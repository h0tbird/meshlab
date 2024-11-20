### Experimenting with `devcontainer`

Install `devcontainer`:
```
brew install devcontainer
```

Open `zsh` inside the container:
```
cd ~/git/h0tbird/meshlab
devcontainer up --workspace-folder .
devcontainer exec --workspace-folder . zsh
```
