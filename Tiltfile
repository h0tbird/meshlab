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
    entrypoint=['/usr/local/bin/pilot-discovery'],
    live_update=[
        sync(binary_full_path, '/usr/local/bin/pilot-discovery'),
    ],
    only=[binary_path],
)

# Patch the istiod deployment to use our Tilt-managed image
# Note: Tilt replaces rather than merges, so we need the full spec
k8s_yaml(blob("""
apiVersion: apps/v1
kind: Deployment
metadata:
  name: istiod-1-28-2
  namespace: istio-system
  labels:
    app: istiod
    istio: pilot
    istio.io/rev: 1-28-2
spec:
  replicas: 1
  selector:
    matchLabels:
      app: istiod
      istio.io/rev: 1-28-2
  strategy:
    rollingUpdate:
      maxSurge: 100%
      maxUnavailable: 25%
  template:
    metadata:
      annotations:
        prometheus.io/port: "15014"
        prometheus.io/scrape: "true"
        sidecar.istio.io/inject: "false"
      labels:
        app: istiod
        istio: istiod
        istio.io/rev: 1-28-2
        istio.io/dataplane-mode: none
        sidecar.istio.io/inject: "false"
    spec:
      serviceAccountName: istiod-1-28-2
      tolerations:
      - key: cni.istio.io/not-ready
        operator: Exists
      containers:
      - name: discovery
        image: pilot-discovery-dev
        args:
        - discovery
        - --monitoringAddr=:15014
        - --log_output_level=default:info
        - --log_as_json
        - --domain
        - pasta.local
        - --keepaliveMaxServerConnectionAge
        - 30m
        env:
        - name: REVISION
          value: 1-28-2
        - name: PILOT_CERT_PROVIDER
          value: istiod
        - name: POD_NAME
          valueFrom:
            fieldRef:
              apiVersion: v1
              fieldPath: metadata.name
        - name: POD_NAMESPACE
          valueFrom:
            fieldRef:
              apiVersion: v1
              fieldPath: metadata.namespace
        - name: SERVICE_ACCOUNT
          valueFrom:
            fieldRef:
              apiVersion: v1
              fieldPath: spec.serviceAccountName
        - name: KUBECONFIG
          value: /var/run/secrets/remote/config
        - name: CA_TRUSTED_NODE_ACCOUNTS
          value: istio-system/ztunnel
        - name: AUTO_RELOAD_PLUGIN_CERTS
          value: "true"
        - name: ENABLE_NATIVE_SIDECARS
          value: "true"
        - name: ISTIOD_CUSTOM_HOST
          value: istiod.pasta-1
        - name: PILOT_ENABLE_AMBIENT
          value: "true"
        - name: PILOT_ENABLE_WORKLOAD_ENTRY_AUTOREGISTRATION
          value: "true"
        - name: PILOT_ENABLE_WORKLOAD_ENTRY_HEALTHCHECKS
          value: "true"
        - name: PILOT_TRACE_SAMPLING
          value: "1"
        - name: PILOT_ENABLE_ANALYSIS
          value: "false"
        - name: CLUSTER_ID
          value: pasta-1
        - name: GOMEMLIMIT
          valueFrom:
            resourceFieldRef:
              divisor: "1"
              resource: limits.memory
        - name: GOMAXPROCS
          valueFrom:
            resourceFieldRef:
              divisor: "1"
              resource: limits.cpu
        - name: PLATFORM
          value: ""
        ports:
        - containerPort: 8080
          name: http-debug
          protocol: TCP
        - containerPort: 15010
          name: grpc-xds
          protocol: TCP
        - containerPort: 15012
          name: tls-xds
          protocol: TCP
        - containerPort: 15017
          name: https-webhooks
          protocol: TCP
        - containerPort: 15014
          name: http-monitoring
          protocol: TCP
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 1
          periodSeconds: 3
          timeoutSeconds: 5
        resources:
          requests:
            cpu: 500m
            memory: 2048Mi
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop:
            - ALL
          readOnlyRootFilesystem: true
          runAsNonRoot: true
        volumeMounts:
        - mountPath: /var/run/secrets/tokens
          name: istio-token
          readOnly: true
        - mountPath: /var/run/secrets/istio-dns
          name: local-certs
        - mountPath: /etc/cacerts
          name: cacerts
          readOnly: true
        - mountPath: /var/run/secrets/remote
          name: istio-kubeconfig
          readOnly: true
        - mountPath: /var/run/secrets/istiod/tls
          name: istio-csr-dns-cert
          readOnly: true
        - mountPath: /var/run/secrets/istiod/ca
          name: istio-csr-ca-configmap
          readOnly: true
      volumes:
      - emptyDir:
          medium: Memory
        name: local-certs
      - name: istio-token
        projected:
          sources:
          - serviceAccountToken:
              audience: istio-ca
              expirationSeconds: 43200
              path: istio-token
      - name: cacerts
        secret:
          optional: true
          secretName: cacerts
      - name: istio-kubeconfig
        secret:
          optional: true
          secretName: istio-kubeconfig
      - name: istio-csr-dns-cert
        secret:
          optional: true
          secretName: istiod-tls
      - name: istio-csr-ca-configmap
        configMap:
          defaultMode: 420
          name: istio-ca-root-cert
          optional: true
"""))

# Configure the k8s resource
k8s_resource(
    workload='istiod-1-28-2',
    new_name='istiod',
    labels=['istio'],
)
