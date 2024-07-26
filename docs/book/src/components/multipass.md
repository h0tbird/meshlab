# Multipass

[Multipass](https://multipass.run/) from Canonical is a tool for launching, managing, and orchestrating Linux virtual machines on local computers, simplifying the process for development, testing, and other purposes. It provides a user-friendly command-line interface and integrates with other tools for automation and customization.


Stop/start multipassd:
```console
sudo launchctl unload /Library/LaunchDaemons/com.canonical.multipassd.plist
sudo launchctl load -w /Library/LaunchDaemons/com.canonical.multipassd.plist
```

Restart multipassd:
```console
sudo launchctl kickstart -k system/com.canonical.multipassd
```

List all available instances:
```console
multipass list
```

Display information about all instances:
```console
multipass info
```

Open a shell on a running instance:
```
multipass shell pasta-1
```

Tail the logs:
```console
sudo tail -f /Library/Logs/Multipass/multipassd.log
```
