# CKA Mock Exam — Answer Key

Each answer lists the fastest exam-viable path, then the trap being tested.

---

## Task 1 — Restore the cluster-2 API server (8%)

```bash
ssh root@c2-cp-1
ls /etc/kubernetes/manifests/
crictl ps -a | grep apiserver          # exited container
crictl logs <container-id>             # or:
journalctl -u kubelet --no-pager | grep -i apiserver | tail -30
```

The log shows the API server cannot open its client CA file. The manifest has been
tampered with:

```bash
grep client-ca /etc/kubernetes/manifests/kube-apiserver.yaml
#   - --client-ca-file=/etc/kubernetes/pki/ca-backup.crt   <-- wrong
ls /etc/kubernetes/pki/ca.crt
```

Fix:

```bash
sed -i 's#--client-ca-file=.*#--client-ca-file=/etc/kubernetes/pki/ca.crt#' \
  /etc/kubernetes/manifests/kube-apiserver.yaml
```

The kubelet watches `/etc/kubernetes/manifests/` and recreates the static pod within
~20 seconds. Verify:

```bash
crictl ps | grep apiserver
kubectl --context cluster-2 get nodes
```

**Trap:** candidates reach for `systemctl restart kubelet` or `kubectl` (which is dead).
Static pods are recovered by editing the manifest and waiting — nothing else is needed.
Also note the file must remain valid YAML; a `crictl ps -a` that shows *no* apiserver
container at all usually means the manifest failed to parse.

---

## Task 2 — Scoped RBAC (5%)

```bash
kubectl create ns build
kubectl create sa ci-bot -n build

kubectl create role ci-role -n build \
  --verb=get,list,watch,create --resource=pods
kubectl create role ci-exec -n build \
  --verb=create --resource=pods/exec

kubectl create rolebinding ci-bind -n build \
  --role=ci-role --serviceaccount=build:ci-bot
kubectl create rolebinding ci-exec-bind -n build \
  --role=ci-exec --serviceaccount=build:ci-bot
```

Verification:

```bash
S=system:serviceaccount:build:ci-bot
kubectl auth can-i create pods       --as=$S -n build      # yes
kubectl auth can-i create pods/exec  --as=$S -n build      # yes
kubectl auth can-i delete pods       --as=$S -n build      # no
kubectl auth can-i list pods         --as=$S -n default    # no
```

**Trap:** `pods/exec` is a *subresource* and is not covered by a rule on `pods`. Two
rules are required (or one Role with two rule blocks). Also: `Role` + `RoleBinding`,
never `ClusterRole` + `ClusterRoleBinding`, or the "no other namespace" requirement fails.

---

## Task 3 — Upgrade a worker node (7%)

```bash
# From the control plane
kubectl drain c1-node-2 --ignore-daemonsets --delete-emptydir-data

# On c1-node-2
ssh root@c1-node-2
apt-mark unhold kubeadm
apt-get update && apt-get install -y kubeadm=1.34.1-1.1
apt-mark hold kubeadm
kubeadm upgrade node

apt-mark unhold kubelet kubectl
apt-get install -y kubelet=1.34.1-1.1 kubectl=1.34.1-1.1
apt-mark hold kubelet kubectl
systemctl daemon-reload
systemctl restart kubelet

# Back on the control plane
kubectl uncordon c1-node-2
kubectl get nodes          # all nodes on the same version
```

Find the exact available version with `apt-cache madison kubeadm | head`.

**Trap:** on a worker it is `kubeadm upgrade node`, **not** `kubeadm upgrade apply`.
`apply` is control-plane only. Forgetting `apt-mark unhold` makes the install silently
no-op. Forgetting `uncordon` leaves the node `Ready,SchedulingDisabled` — partial credit.

---

## Task 4 — Helm release lifecycle (4%)

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
helm install frontend bitnami/nginx -n shop --create-namespace --set replicaCount=2
helm upgrade frontend bitnami/nginx -n shop --set replicaCount=4
helm rollback frontend 1 -n shop
mkdir -p /opt/cka && helm history frontend -n shop > /opt/cka/task4-history.txt
```

**Trap:** a rollback creates a *new* revision (3) rather than rewinding to 1 — the exam
text asks for revision 3 to be current, which is exactly what a correct rollback produces.
`helm rollback frontend` with no revision number goes to the previous release, which here
happens to be the same thing, but state the revision explicitly.

---

## Task 5 — Kustomize overlay (5%)

```bash
mkdir -p /opt/cka/kustomize/overlays/prod
cat > /opt/cka/kustomize/overlays/prod/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: prod
resources:
  - ../../base
labels:
  - pairs:
      tier: frontend
    includeSelectors: false
images:
  - name: nginx
    newTag: "1.27"
replicas:
  - name: catalog
    count: 4
EOF

kubectl kustomize /opt/cka/kustomize/overlays/prod    # preview
kubectl apply -k /opt/cka/kustomize/overlays/prod
```

**Trap:** `commonLabels` is deprecated in current Kustomize and, more importantly, injects
the label into the Deployment's immutable `selector`, which breaks re-apply. Use `labels:`
with `includeSelectors: false`. Also: `images:` matches on the image *name*, not the
container name.

---

## Task 6 — CRD and custom resource (4%)

```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: backups.stable.example.com
spec:
  group: stable.example.com
  scope: Namespaced
  names:
    plural: backups
    singular: backup
    kind: Backup
    shortNames: ["bk"]
  versions:
    - name: v1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              required: ["schedule"]
              properties:
                schedule:
                  type: string
                retentionDays:
                  type: integer
```

```yaml
apiVersion: stable.example.com/v1
kind: Backup
metadata:
  name: nightly
  namespace: ops
spec:
  schedule: "0 3 * * *"
  retentionDays: 14
```

**Trap:** `metadata.name` of the CRD must be exactly `<plural>.<group>`. The structural
schema requires a top-level `type: object`; omitting it is rejected. `required` sits inside
the `spec` object schema, not at the root.

---

## Task 7 — Constrained scheduling (6%)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: trainer
  namespace: ml
spec:
  replicas: 2
  selector:
    matchLabels: {app: trainer}
  template:
    metadata:
      labels: {app: trainer}
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  - key: accelerator
                    operator: In
                    values: ["nvidia"]
      tolerations:
        - key: hardware
          operator: Equal
          value: gpu
          effect: NoSchedule
      containers:
        - name: trainer
          image: busybox:1.36
          command: ["sleep", "3600"]
          resources:
            requests: {cpu: 250m, memory: 256Mi}
            limits:   {cpu: 500m, memory: 512Mi}
```

**Trap:** the toleration and the affinity do different jobs. A toleration alone permits
scheduling onto the tainted node but does not *require* it — replicas would scatter. Node
affinity alone leaves the pods `Pending` because the taint still repels them. Both are
mandatory. `requiredDuringScheduling...`, not `preferred`.

---

## Task 8 — Configuration injection (5%)

```bash
kubectl create ns billing
kubectl create configmap billing-config -n billing \
  --from-literal=APP_ENV=production --from-literal=LOG_LEVEL=debug
kubectl create secret generic billing-creds -n billing \
  --from-literal=DB_USER=billing --from-literal='DB_PASS=Tr0ub4dor&3'
```

```yaml
apiVersion: v1
kind: Pod
metadata: {name: invoicer, namespace: billing}
spec:
  containers:
    - name: invoicer
      image: busybox:1.36
      command: ["sleep", "3600"]
      envFrom:
        - configMapRef: {name: billing-config}
      env:
        - name: DATABASE_USER
          valueFrom:
            secretKeyRef: {name: billing-creds, key: DB_USER}
      volumeMounts:
        - name: creds
          mountPath: /etc/billing
          readOnly: true
  volumes:
    - name: creds
      secret: {secretName: billing-creds}
```

**Trap:** quote the password on the shell — the `&` backgrounds the command otherwise.
`envFrom` for the whole ConfigMap, `env` + `secretKeyRef` for the single remapped key;
mixing them up loses points.

---

## Task 9 — Rollout and rollback (4%)

```bash
kubectl -n retail patch deploy storefront -p \
  '{"spec":{"strategy":{"type":"RollingUpdate","rollingUpdate":{"maxSurge":1,"maxUnavailable":0}}}}'

kubectl -n retail set image deploy/storefront nginx=nginx:1.27
kubectl -n retail rollout status deploy/storefront

kubectl -n retail set image deploy/storefront nginx=nginx:1.99-doesnotexist
kubectl -n retail rollout status deploy/storefront --timeout=60s   # fails

kubectl -n retail rollout history deploy/storefront
kubectl -n retail rollout history deploy/storefront --revision=2   # confirm 1.27
kubectl -n retail rollout undo deploy/storefront --to-revision=2
kubectl -n retail rollout status deploy/storefront

kubectl -n retail rollout history deploy/storefront | tail -1 | awk '{print $1}' \
  > /opt/cka/task9-revision.txt
```

**Trap:** `rollout undo` with no `--to-revision` returns to the *immediately preceding*
revision, which is the broken 1.27→1.99 predecessor only by luck of ordering. Inspect
`rollout history --revision=N` and target explicitly. Note `maxUnavailable: 0` is why the
bad rollout stalls instead of taking the service down — that is the point of the setting.

---

## Task 10 — Network policy (7%)

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: default-deny-ingress, namespace: payments}
spec:
  podSelector: {}
  policyTypes: ["Ingress"]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: allow-frontend-to-ledger, namespace: payments}
spec:
  podSelector:
    matchLabels: {app: ledger}
  policyTypes: ["Ingress"]
  ingress:
    - from:
        - podSelector:
            matchLabels: {role: frontend}
      ports:
        - protocol: TCP
          port: 8080
```

Verify:

```bash
kubectl -n payments exec deploy/frontend -- wget -qO- --timeout=3 ledger:8080   # works
kubectl -n payments exec deploy/scanner  -- wget -qO- --timeout=3 ledger:8080   # times out
```

**Trap 1:** `policyTypes: ["Ingress"]` with no `ingress:` block is deny-all; adding an
empty `ingress: []` means the same thing but `ingress: [{}]` means *allow all*. Watch the
brackets.
**Trap 2:** the `from` and `ports` entries must be in the **same** ingress rule. Splitting
them into two list items under `ingress:` means "from frontend on any port" OR "from
anywhere on 8080" — a much wider policy that still passes a naive smoke test.
**Trap 3:** this only works because the lab runs Calico. Flannel silently ignores
NetworkPolicy and every test would appear to "pass" while enforcing nothing.

---

## Task 11 — Services and endpoints (6%)

```bash
# Add the port name if absent
kubectl -n inventory patch deploy stock-api --type=json -p \
  '[{"op":"add","path":"/spec/template/spec/containers/0/ports","value":[{"name":"http","containerPort":9090}]}]'
```

```yaml
apiVersion: v1
kind: Service
metadata: {name: stock-svc, namespace: inventory}
spec:
  selector: {app: stock-api}
  ports:
    - port: 80
      targetPort: http        # by name
---
apiVersion: v1
kind: Service
metadata: {name: stock-nodeport, namespace: inventory}
spec:
  type: NodePort
  selector: {app: stock-api}
  ports:
    - port: 80
      targetPort: http
      nodePort: 31090
```

```bash
kubectl -n inventory get endpointslices -l kubernetes.io/service-name=stock-svc
kubectl -n inventory get svc stock-svc -o jsonpath='{.spec.clusterIP}' \
  > /opt/cka/task11-clusterip.txt
```

**Trap:** a named `targetPort` only resolves if the *pod spec* declares that port name.
Naming the Service port is not enough. `kubectl get endpoints` is deprecated in favour of
`kubectl get endpointslices`; both still work in 1.34 but know the newer one.

---

## Task 12 — Gateway API (7%)

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: {name: edge-gw, namespace: edge}
spec:
  gatewayClassName: cka-gc
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      allowedRoutes:
        namespaces:
          from: All
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: shop-route, namespace: inventory}
spec:
  parentRefs:
    - name: edge-gw
      namespace: edge
      sectionName: http
  hostnames: ["shop.example.com"]
  rules:
    - matches:
        - path: {type: PathPrefix, value: /api}
      backendRefs:
        - name: stock-svc
          port: 80
    - matches:
        - path: {type: PathPrefix, value: /}
      backendRefs:
        - name: stock-svc
          port: 80
          weight: 100
```

**Trap:** the HTTPRoute lives in `inventory` but the Gateway lives in `edge`, so
`parentRefs` **must** carry `namespace: edge`. That cross-namespace attachment is only
permitted because the listener sets `allowedRoutes.namespaces.from: All` — without it the
route is created but reports `NotAllowedByListeners`. Check with:

```bash
kubectl -n inventory describe httproute shop-route | grep -A5 Conditions
```

---

## Task 13 — Bind a pending claim (5%)

```bash
kubectl -n observability get pvc logs-pvc -o yaml | grep -E 'storageClassName|storage:|accessModes' -A2
```

The claim asks for 2Gi, `ReadWriteOnce`, class `local-fast`. Create a PV matching **all
three** axes:

```yaml
apiVersion: v1
kind: PersistentVolume
metadata: {name: logs-pv}
spec:
  capacity: {storage: 2Gi}
  accessModes: ["ReadWriteOnce"]
  storageClassName: local-fast
  persistentVolumeReclaimPolicy: Retain
  hostPath: {path: /mnt/logs}
```

**Trap:** capacity must be *greater than or equal to* the request, but access mode and
storage class must match **exactly**. A PV with no `storageClassName` will never bind to a
PVC that names one. This is the single most common storage failure on the exam.

---

## Task 14 — StorageClass and deferred binding (5%)

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata: {name: local-delayed}
provisioner: kubernetes.io/no-provisioner
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
---
apiVersion: v1
kind: PersistentVolume
metadata: {name: local-pv-a}
spec:
  capacity: {storage: 1Gi}
  accessModes: ["ReadWriteOnce"]
  storageClassName: local-delayed
  local: {path: /mnt/local-a}
  nodeAffinity:
    required:
      nodeSelectorTerms:
        - matchExpressions:
            - key: kubernetes.io/hostname
              operator: In
              values: ["c2-node-1"]
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: app-data, namespace: default}
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: local-delayed
  resources:
    requests: {storage: 1Gi}
---
apiVersion: v1
kind: Pod
metadata: {name: consumer, namespace: default}
spec:
  containers:
    - name: consumer
      image: busybox:1.36
      command: ["sleep", "3600"]
      volumeMounts:
        - {name: data, mountPath: /data}
  volumes:
    - name: data
      persistentVolumeClaim: {claimName: app-data}
```

**Trap:** a `local` volume **requires** `nodeAffinity` — the API server rejects it
otherwise. Between applying the PVC and the Pod, `kubectl get pvc` shows `Pending`; that is
correct behaviour for `WaitForFirstConsumer`, not a fault. `hostPath` would also bind but
does not satisfy the node-affinity requirement of the task.

---

## Task 15 — Recover a NotReady node (7%)

```bash
kubectl describe node c1-node-1 | grep -A10 Conditions
ssh root@c1-node-1
systemctl status kubelet                       # activating (auto-restart) / failed
journalctl -u kubelet --no-pager -n 40
```

The log shows a kubelet config parse failure, e.g.
`failed to load Kubelet config file /var/lib/kubelet/config.yaml`.

```bash
tail -5 /var/lib/kubelet/config.yaml           # malformed trailing block
vi /var/lib/kubelet/config.yaml                # delete the offending lines
systemctl restart kubelet
systemctl is-active kubelet
```

```bash
echo "Malformed YAML appended to /var/lib/kubelet/config.yaml prevented kubelet startup" \
  > /opt/cka/task15-cause.txt      # on c1-cp-1
```

**Trap:** `systemctl status` alone shows only "failed"; the actionable error is in
`journalctl -u kubelet`. Candidates who jump straight to `kubeadm reset` and rejoin lose
full marks even though the node ends up `Ready` — the task forbids it, and in production it
would destroy node state.

---

## Task 16 — Service with no endpoints (7%)

```bash
kubectl -n checkout get svc checkout-svc -o yaml
kubectl -n checkout get endpointslices -l kubernetes.io/service-name=checkout-svc
kubectl -n checkout get pods --show-labels
kubectl -n checkout get deploy checkout -o jsonpath='{.spec.template.spec.containers[0].ports}'
```

Two independent faults: the Service selector reads `app=checkout-api` while the pods carry
`app=checkout`, and the `targetPort` is `8080` while the container listens on `80`.

```bash
kubectl -n checkout patch svc checkout-svc -p \
  '{"spec":{"selector":{"app":"checkout"},"ports":[{"port":80,"targetPort":80,"protocol":"TCP"}]}}'
```

Verify:

```bash
kubectl -n checkout run t --rm -it --image=busybox:1.36 --restart=Never \
  -- wget -qO- checkout-svc.checkout.svc.cluster.local
```

**Trap:** fixing only the selector produces endpoints, which looks like success in
`kubectl get endpointslices`, but traffic still fails on the wrong `targetPort`. Always
check both the selector *and* the port mapping — an empty endpoint list points at the
selector, a populated list plus connection-refused points at the port.

---

## Task 17 — CrashLoopBackOff and resource reporting (8%)

**Part A**

```bash
kubectl -n analytics get pods
kubectl -n analytics logs deploy/reporting --previous
# cat: can't open '/config/app.conf': No such file or directory
kubectl -n analytics describe pod <pod> | grep -A6 Mounts
kubectl -n analytics get cm reporting-config -o yaml
```

The ConfigMap key is `app.config`; the container reads `/config/app.conf`. Fix either side —
renaming the key is cleanest:

```bash
kubectl -n analytics get cm reporting-config -o json \
  | jq '.data["app.conf"] = .data["app.config"] | del(.data["app.config"])' \
  | kubectl apply -f -
kubectl -n analytics rollout restart deploy/reporting
```

Or add an explicit `items` mapping to the volume:

```yaml
volumes:
  - name: config
    configMap:
      name: reporting-config
      items:
        - key: app.config
          path: app.conf
```

**Part B**

```bash
kubectl top pods -A --sort-by=memory | head -2
echo "<namespace>/<pod-name>" > /opt/cka/task17-topmem.txt
```

**Trap:** `kubectl logs` on a CrashLoopBackOff pod returns the *current* container, which
may not have started. `--previous` is what surfaces the failure. `kubectl top` needs
metrics-server; it is preinstalled here, but on a real exam an empty result usually means
you are looking at a cluster where it is not deployed rather than a real zero.

---

## Grading

```bash
./ansible/grade.sh          # scores all 17 tasks, prints weighted total
```

Re-arm any single task for another attempt:

```bash
cd ansible
ansible-playbook repair.yml -t <tag>    # reset to healthy
ansible-playbook break.yml  -t <tag>    # break again
```

Tags: `apiserver`, `kubelet`, `skew`, `endpoints`, `crashloop`, `pvc`.
