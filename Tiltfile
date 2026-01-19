load('ext://restart_process', 'docker_build_with_restart')

#------------------------------------------------------------------------------
# Restrict to local Kind cluster contexts only
#------------------------------------------------------------------------------

allow_k8s_contexts([
    'kind-pasta-1',
    'kind-pasta-2',
    'kind-pizza-1',
    'kind-pizza-2',
])

#------------------------------------------------------------------------------
# Variables
#------------------------------------------------------------------------------

istio_version = '1-29-0-alpha-0'
istio_dotted = istio_version.replace('-', '.')
image_ref = 'pilot-discovery-dev'
cluster_name = k8s_context().removeprefix('kind-')

#------------------------------------------------------------------------------
# Determine architecture and binary path
#------------------------------------------------------------------------------

arch = str(local('dpkg --print-architecture', quiet=True)).strip()
istio_dir = '../istio'
binary_path = 'out/linux_' + arch + '/pilot-discovery'
binary_full_path = istio_dir + '/' + binary_path

print('Detected architecture: ' + arch)
print('Watching pilot-discovery binary at: ' + binary_full_path)

#------------------------------------------------------------------------------
# Build image with restart capability for live updates
#------------------------------------------------------------------------------

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

#------------------------------------------------------------------------------
# The YAML below matches the configuration applied by ArgoCD for the istiod
# deployment. When Tilt detects a matching image_ref, it mutates this YAML to
# inject its live sync functionality. You can then check the diff in ArgoCD to
# see exactly what was modified.
#------------------------------------------------------------------------------

k8s_yaml(blob("""
apiVersion: apps/v1
kind: Deployment
metadata:
  name: istiod-{istio_version}
  namespace: istio-system
  annotations:
    argocd.argoproj.io/tracking-id: {cluster_name}-istio-istiod:apps/Deployment:istio-system/istiod-{istio_version}
  labels:
    app: istiod
    app.kubernetes.io/instance: istio-istiod
    app.kubernetes.io/managed-by: Helm
    app.kubernetes.io/name: istiod
    app.kubernetes.io/part-of: istio
    app.kubernetes.io/version: {istio_dotted}
    helm.sh/chart: istiod-{istio_dotted}
    install.operator.istio.io/owning-resource: unknown
    istio: pilot
    istio.io/rev: {istio_version}
    operator.istio.io/component: Pilot
    release: istio-istiod
spec:
  replicas: 1
  selector:
    matchLabels:
      app: istiod
      istio.io/rev: {istio_version}
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
        app.kubernetes.io/instance: istio-istiod
        app.kubernetes.io/managed-by: Helm
        app.kubernetes.io/name: istiod
        app.kubernetes.io/part-of: istio
        app.kubernetes.io/version: {istio_dotted}
        helm.sh/chart: istiod-{istio_dotted}
        install.operator.istio.io/owning-resource: unknown
        istio: istiod
        istio.io/dataplane-mode: none
        istio.io/rev: {istio_version}
        operator.istio.io/component: Pilot
        sidecar.istio.io/inject: "false"
    spec:
      serviceAccountName: istiod-{istio_version}
      tolerations:
      - key: cni.istio.io/not-ready
        operator: Exists
      containers:
      - name: discovery
        image: {image_ref}
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
          value: {istio_version}
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
          value: istiod.{cluster_name}
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
          value: {cluster_name}
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
""".format(image_ref=image_ref, istio_version=istio_version, istio_dotted=istio_dotted, cluster_name=cluster_name)))

#------------------------------------------------------------------------------
# Configure the k8s resource
#------------------------------------------------------------------------------

k8s_resource(
    workload='istiod-' + istio_version,
    new_name='istiod',
    labels=['istio'],
)
