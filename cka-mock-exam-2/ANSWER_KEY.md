# CKA Mock Exam 2 — Answer Key

## Task 1 — Restore the cluster-1 Scheduler

1. SSH to `c1-cp-1`.
2. Check the status of static pods: `kubectl get pods -n kube-system`.
3. If `kube-scheduler` is missing or crashing, check `/etc/kubernetes/manifests/kube-scheduler.yaml`.
4. (Assuming the fault is a typo in the manifest): Correct the typo (e.g., image name or flag).
5. The kubelet will automatically restart the pod.
6. Verify: `kubectl get pods -n kube-system` shows `kube-scheduler` as Running.
7. Verify: `kubectl get pods -A` shows pods are now being scheduled.

## Task 2 — Developer Permissions

```bash
kubectl create namespace development
kubectl create sa dev-sa -n development

cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: development
  name: dev-role
rules:
- apiGroups: ["apps", ""]
  resources: ["deployments", "services"]
  verbs: ["*"]
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: dev-bind
  namespace: development
subjects:
- kind: ServiceAccount
  name: dev-sa
  namespace: development
roleRef:
  kind: Role
  name: dev-role
  apiGroup: rbac.authorization.k8s.io
EOF
```

## Task 3 — Upgrade Control Plane

1. SSH to `c2-cp-1`.
2. Find the latest version: `apt-cache madison kubeadm`.
3. Upgrade kubeadm: `apt-get update && apt-get install -y kubeadm=1.34.x-1.1` (replace x with latest).
4. Plan the upgrade: `kubeadm upgrade plan`.
5. Apply the upgrade: `kubeadm upgrade apply v1.34.x`.
6. Upgrade kubelet and kubectl: `apt-get install -y kubelet=1.34.x-1.1 kubectl=1.34.x-1.1`.
7. Restart kubelet: `systemctl daemon-reload && systemctl restart kubelet`.

## Task 4 — Static Pod

1. SSH to `c1-node-2`.
2. Find the kubelet config path: `ps aux | grep kubelet` (look for `--config`).
3. Check the `staticPodPath` in that config (usually `/etc/kubernetes/manifests`).
4. Create the manifest:
```bash
cat <<EOF > /etc/kubernetes/manifests/monitor.yaml
apiVersion: v1
kind: Pod
metadata:
  name: monitor
spec:
  containers:
  - name: monitor
    image: busybox:1.36
    command: ["sleep", "3600"]
EOF
```

## Task 5 — Sidecar Container for Logging

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: legacy-app
  namespace: apps
spec:
  replicas: 1
  selector:
    matchLabels:
      app: legacy
  template:
    metadata:
      labels:
        app: legacy
    spec:
      volumes:
      - name: log-vol
        emptyDir: {}
      containers:
      - name: main-app
        image: busybox:1.36
        command: ["sh", "-c", "while true; do date >> /var/log/app.log; sleep 1; done"]
        volumeMounts:
        - name: log-vol
          mountPath: /var/log
      - name: log-tailer
        image: busybox:1.36
        command: ["sh", "-c", "tail -f /var/log/app.log"]
        volumeMounts:
        - name: log-vol
          mountPath: /var/log
```

## Task 6 — Ingress Resource

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: front-ingress
  namespace: production
spec:
  rules:
  - host: app.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: front-svc
            port:
              number: 80
```

## Task 7 — Taints and Tolerations

```bash
kubectl taint nodes c2-node-1 tier=gold:NoSchedule
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: gold-pod
  namespace: default
spec:
  nodeSelector:
    kubernetes.io/hostname: c2-node-1
  tolerations:
  - key: "tier"
    operator: "Equal"
    value: "gold"
    effect: "NoSchedule"
  containers:
  - name: nginx
    image: nginx:1.27
```

## Task 8 — Persistent Volumes and Claims

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: manual-pv
spec:
  capacity:
    storage: 2Gi
  volumeMode: Filesystem
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: manual
  hostPath:
    path: /data/pv-data
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: manual-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  volumeMode: Filesystem
  resources:
    requests:
      storage: 2Gi
  storageClassName: manual
```

## Task 9 — Troubleshooting: Kubelet Service

1. SSH to `c2-node-1`.
2. Check kubelet status: `systemctl status kubelet`.
3. If stopped: `systemctl start kubelet`.
4. If failing, check logs: `journalctl -u kubelet`.
5. (Assuming the fault is a wrong config file path or similar): Fix the service file or config and restart.
6. Verify: `kubectl get nodes` shows `c2-node-1` as `Ready`.

## Task 10 — ExternalName Service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: db-external
  namespace: legacy
spec:
  type: ExternalName
  externalName: database.internal.example.com
```

## Task 11 — Egress Network Policy

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: egress-lock
  namespace: restricted
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - ipBlock:
        cidr: 10.10.10.10/32
    ports:
    - protocol: UDP
      port: 53
```

## Task 12 — ConfigMap and Secret Integration

```bash
kubectl create namespace config-env
kubectl create configmap app-settings -n config-env --from-literal=theme=dark
kubectl create secret generic app-creds -n config-env --from-literal=api-key=S3cr3t
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app-runner
  namespace: config-env
spec:
  containers:
  - name: nginx
    image: nginx:1.27
    env:
    - name: APP_THEME
      valueFrom:
        configMapKeyRef:
          name: app-settings
          key: theme
    volumeMounts:
    - name: creds-vol
      mountPath: /etc/creds
      readOnly: true
  volumes:
  - name: creds-vol
    secret:
      secretName: app-creds
```

## Task 13 — Horizontal Pod Autoscaler

```bash
kubectl autoscale deployment cpu-load -n scaling --cpu-percent=60 --min=2 --max=5
```

## Task 14 — Cluster-wide Event Access

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: event-reader
rules:
- apiGroups: [""]
  resources: ["events"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: alice-event-access
subjects:
- kind: User
  name: alice
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: event-reader
  apiGroup: rbac.authorization.k8s.io
```

## Task 15 — Service Port Mismatch

1. Edit the Service: `kubectl edit svc backend-svc -n api`.
2. Change `targetPort` from `8080` to `9090`.

## Task 16 — StorageClass with Retain Policy

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: archive-storage
provisioner: kubernetes.io/no-provisioner
reclaimPolicy: Retain
volumeBindingMode: WaitForFirstConsumer
```

## Task 17 — CrashLoopBackOff: Missing Environment Variable

1. Edit the Deployment: `kubectl edit deploy data-worker -n ops`.
2. Add the environment variable:
```yaml
spec:
  template:
    spec:
      containers:
      - name: worker
        env:
        - name: DATABASE_URL
          value: "postgres://db.example.com:5432"
```
