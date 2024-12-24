# Cloud-init

[cloud-init](https://cloudinit.readthedocs.io/en/latest) is a tool used to configure virtual machine instances in the cloud during their first boot. It simplifies the provisioning process, enabling quick setup of new environments with desired configurations. The following commands provide examples for monitoring and inspecting the cloud-init process on various nodes in the system, including logs and scripts run during the instance's first boot.

Tail the `cloud-init` logs:
```console
multipass exec mnger-1 -- tail -f /var/log/cloud-init-output.log
multipass exec pasta-1 -- tail -f /var/log/cloud-init-output.log
multipass exec pasta-2 -- tail -f /var/log/cloud-init-output.log
```

Inspect the rendered `runcmd`:
```console
multipass exec mnger-1 -- sudo cat /var/lib/cloud/instance/scripts/runcmd
multipass exec pasta-1 -- sudo cat /var/lib/cloud/instance/scripts/runcmd
multipass exec pasta-2 -- sudo cat /var/lib/cloud/instance/scripts/runcmd
multipass exec virt-01 -- sudo cat /var/lib/cloud/instance/scripts/runcmd
```
