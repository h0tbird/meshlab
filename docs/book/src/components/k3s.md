# k3s

[k3s](https://k3s.io) is a lightweight version of Kubernetes designed for resource-constrained environments like IoT devices and edge computing. It requires fewer resources and has additional features such as simplified installation and compatibility with ARM architectures.

Run config check:
```console
multipass exec pasta-1 -- bash -c "sudo k3s check-config"
multipass exec pasta-2 -- bash -c "sudo k3s check-config"
```