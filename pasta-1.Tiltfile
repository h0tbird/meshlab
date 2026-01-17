# Tilt Live-Update for pilot-discovery
# Watches externally-built pilot-discovery binary and live-syncs into istiod container

load('ext://restart_process', 'docker_build_with_restart')

# Architecture detection
arch = str(local('uname -m', quiet=True)).strip()
if arch == 'x86_64':
    arch = 'amd64'
elif arch == 'aarch64':
    arch = 'arm64'

print('Detected architecture: ' + arch)

# Paths
istio_dir = '../istio'
binary_path = 'out/linux_' + arch + '/pilot-discovery'
binary_full_path = istio_dir + '/' + binary_path

# Image reference for Tilt-managed image
image_ref = 'pilot-discovery-dev'

# Build image with restart capability for live updates
docker_build_with_restart(
    ref=image_ref,
    context=istio_dir,
    dockerfile='hack/Dockerfile.pilot-discovery-tilt',
    build_args={'TARGETARCH': arch},
    entrypoint=['/usr/local/bin/pilot-discovery', 'discovery'],
    live_update=[
        sync(binary_full_path, '/usr/local/bin/pilot-discovery'),
    ],
    only=[binary_path],
)

# Patch the istiod deployment to use our Tilt-managed image
k8s_yaml(blob("""
apiVersion: apps/v1
kind: Deployment
metadata:
  name: istiod-1-28-2
  namespace: istio-system
spec:
  template:
    spec:
      containers:
      - name: discovery
        image: pilot-discovery-dev
"""))

# Configure the k8s resource
k8s_resource(
    workload='istiod-1-28-2',
    new_name='istiod',
    labels=['istio'],
)
