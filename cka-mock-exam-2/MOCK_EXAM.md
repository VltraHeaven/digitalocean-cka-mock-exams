# CKA Mock Exam 2 — Kubernetes v1.34

**Duration: 2 hours · 17 tasks · Passing score: 66%**

---

## Before you start

- Two clusters are available: `cluster-1` and `cluster-2`. **Every task names its context.**
- Switch context before each task: `kubectl config use-context <context>`
- SSH to nodes as root: `ssh root@<node>`. Node names resolve via `/etc/hosts`.
- Allowed resources: `kubernetes.io/docs`, `kubernetes.io/blog`, `helm.sh/docs` only.
- Partial credit applies. Attempt everything.

**Node inventory**

| Cluster | Node | Role |
|---|---|---|
| cluster-1 | `c1-cp-1` | control plane |
| cluster-1 | `c1-node-1` | worker |
| cluster-1 | `c1-node-2` | worker |
| cluster-2 | `c2-cp-1` | control plane |
| cluster-2 | `c2-node-1` | worker |

---

## Task 1 — Restore the cluster-1 Scheduler

**Weight: 8% · Context: `cluster-1`**

Pods in `cluster-1` are stuck in `Pending` even though nodes are `Ready` and have sufficient resources.

Diagnose and restore the functionality of the cluster scheduler. You have root SSH on `c1-cp-1`.

The task is complete when newly created pods in any namespace are correctly scheduled and move to `Running`.

---

## Task 2 — Developer Permissions

**Weight: 5% · Context: `cluster-1`**

In namespace `development`:

1. Create a ServiceAccount named `dev-sa`.
2. Create a Role named `dev-role` that allows full management (`*`) of `deployments` and `services`.
3. The Role should also allow only `get` and `list` operations on `secrets`.
4. Bind the `dev-role` to the `dev-sa` using a RoleBinding named `dev-bind`.

---

## Task 3 — Upgrade Control Plane

**Weight: 7% · Context: `cluster-2`**

Upgrade the control plane node `c2-cp-1` to the latest available patch version of Kubernetes `v1.34`.

Follow the official upgrade procedure: upgrade kubeadm, then use `kubeadm upgrade apply`, then upgrade kubelet and kubectl.

Do not upgrade worker nodes.

---

## Task 4 — Static Pod

**Weight: 4% · Context: `cluster-1`**

Create a static pod named `monitor` on worker node `c1-node-2`.

- Image: `busybox:1.36`
- Command: `sleep 3600`
- The pod should be managed by the kubelet on `c1-node-2` directly.

---

## Task 5 — Sidecar Container for Logging

**Weight: 5% · Context: `cluster-1`**

A Deployment named `legacy-app` in namespace `apps` runs a container that writes logs to `/var/log/app.log`.

Add a sidecar container named `log-tailer` to this Deployment:

- Image: `busybox:1.36`
- Command: `sh -c "tail -f /var/log/app.log"`
- Use an `emptyDir` volume named `log-vol` shared between both containers to exchange the log file.
- The main container should mount this volume at `/var/log`.

---

## Task 6 — Ingress Resource

**Weight: 7% · Context: `cluster-1`**

Create an Ingress resource named `front-ingress` in namespace `production`:

- Host: `app.example.com`
- Path: `/`
- Path type: `Prefix`
- Service: `front-svc` on port 80
- The Ingress must be created in the `production` namespace.

---

## Task 7 — Taints and Tolerations

**Weight: 6% · Context: `cluster-2`**

1. Taint the node `c2-node-1` with the key `tier`, value `gold`, and effect `NoSchedule`.
2. Create a Pod named `gold-pod` in namespace `default`:
   - Image: `nginx:1.27`
   - The pod must tolerate the `tier=gold:NoSchedule` taint.
   - Use `nodeSelector` to ensure the pod is scheduled on `c2-node-1`.

---

## Task 8 — Persistent Volumes and Claims

**Weight: 5% · Context: `cluster-1`**

1. Create a PersistentVolume named `manual-pv`:
   - Capacity: `2Gi`
   - Access Mode: `ReadWriteOnce`
   - Reclaim Policy: `Retain`
   - StorageClass: `manual`
   - HostPath: `/data/pv-data` (ensure this directory exists on the host where the PV is provisioned, or assume it will be created).
2. Create a PersistentVolumeClaim named `manual-pvc` in namespace `default`:
   - Request: `2Gi`
   - Access Mode: `ReadWriteOnce`
   - StorageClass: `manual`

---

## Task 9 — Troubleshooting: Kubelet Service

**Weight: 7% · Context: `cluster-2`**

Node `c2-node-1` is in `NotReady` state. Investigate and fix the issue.

The node should be brought back to `Ready` state. Do not reinstall the node or the cluster.

---

## Task 10 — ExternalName Service

**Weight: 5% · Context: `cluster-2`**

Create a Service named `db-external` in namespace `legacy`:

- Type: `ExternalName`
- ExternalName: `database.internal.example.com`

---

## Task 11 — Egress Network Policy

**Weight: 8% · Context: `cluster-2`**

In namespace `restricted`, create a NetworkPolicy named `egress-lock`:

- It should apply to all pods in the namespace.
- It should allow egress traffic **only** to the IP `10.10.10.10` on port `53` (UDP).
- All other egress traffic should be denied.
- Ingress traffic should not be affected by this policy.

---

## Task 12 — ConfigMap and Secret Integration

**Weight: 4% · Context: `cluster-1`**

In namespace `config-env`:

1. Create a ConfigMap `app-settings` with `theme=dark`.
2. Create a Secret `app-creds` with `api-key=S3cr3t`.
3. Create a Pod `app-runner` using image `nginx:1.27`:
   - Inject the ConfigMap key `theme` as an environment variable `APP_THEME`.
   - Mount the Secret as a volume at `/etc/creds` (read-only).

---

## Task 13 — Horizontal Pod Autoscaler

**Weight: 5% · Context: `cluster-2`**

Create a HorizontalPodAutoscaler for Deployment `cpu-load` in namespace `scaling`:

- Min replicas: `2`
- Max replicas: `5`
- Target CPU utilization: `60%`

The Deployment `cpu-load` already exists.

---

## Task 14 — Cluster-wide Event Access

**Weight: 5% · Context: `cluster-1`**

Create a ClusterRole named `event-reader` that allows `get`, `list`, and `watch` on `events` across the entire cluster.

Bind this ClusterRole to the user `alice` using a ClusterRoleBinding named `alice-event-access`.

---

## Task 15 — Service Port Mismatch

**Weight: 7% · Context: `cluster-2`**

Service `backend-svc` in namespace `api` is not reaching the pods of Deployment `backend`.

- The pods are listening on port `9090`.
- The Service is currently configured to target port `8080`.

Fix the Service so it correctly routes traffic to the pods. Do not modify the Deployment.

---

## Task 16 — StorageClass with Retain Policy

**Weight: 4% · Context: `cluster-1`**

Create a StorageClass named `archive-storage`:

- Provisioner: `kubernetes.io/no-provisioner`
- Reclaim Policy: `Retain`
- Volume Binding Mode: `WaitForFirstConsumer`

---

## Task 17 — CrashLoopBackOff: Missing Environment Variable

**Weight: 8% · Context: `cluster-1`**

Deployment `data-worker` in namespace `ops` is in `CrashLoopBackOff`.

The application expects an environment variable `DATABASE_URL` to be present.

Fix the Deployment by adding the missing environment variable with the value `postgres://db.example.com:5432`.

---

## Scoring

| Domain | Tasks | Weight |
|---|---|---|
| Cluster Architecture, Installation & Configuration | 2, 3, 4, 14, 16 | 25% |
| Workloads & Scheduling | 5, 7, 12, 13 | 20% |
| Services & Networking | 6, 10, 11 | 20% |
| Storage | 8 | 5% |
| Troubleshooting | 1, 9, 15, 17 | 30% |

Run `./ansible/grade.sh` from the repo root to score yourself automatically.
