# CKA Mock Exam — Kubernetes v1.34

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

> **Dependency notice:** Task 1 restores the `cluster-2` API server. Tasks 5, 6, 10, 11, 12, 13 and 14 cannot be completed until it is fixed. Do Task 1 first.

---

## Task 1 — Restore the cluster-2 API server

**Weight: 8% · Context: `cluster-2`**

`kubectl` against `cluster-2` fails with a connection error on port 6443. You have root SSH on `c2-cp-1`.

Diagnose and restore API server availability. Do not reinitialise the cluster, do not restore from a backup, and do not change any other component's configuration.

The task is complete when `kubectl --context cluster-2 get nodes` returns both nodes as `Ready`.

---

## Task 2 — Scoped RBAC for a CI service account

**Weight: 5% · Context: `cluster-1`**

In namespace `build`:

1. Create a ServiceAccount named `ci-bot`.
2. Grant it — **within `build` only** — the ability to `get`, `list`, `watch` and `create` pods, and to `create` `pods/exec`.
3. It must **not** be able to delete pods, and must have no permissions in any other namespace.

Verify your work with `kubectl auth can-i`.

---

## Task 3 — Upgrade a worker node

**Weight: 7% · Context: `cluster-1`**

Node `c1-node-2` is running an older patch of Kubernetes than the rest of `cluster-1`.

Upgrade `c1-node-2` to match the control plane version (`v1.34.x`). Follow the correct order of operations: mark the node unschedulable and evict workloads, upgrade the node's kubeadm configuration, upgrade the kubelet and kubectl binaries, then return the node to service.

Do not upgrade the control plane. Do not delete the node from the cluster.

---

## Task 4 — Helm release lifecycle

**Weight: 4% · Context: `cluster-1`**

Using Helm:

1. Add the repository `https://charts.bitnami.com/bitnami` under the name `bitnami`.
2. Install the `bitnami/nginx` chart as release `frontend` into namespace `shop` (create the namespace), with `replicaCount` set to `2`.
3. Upgrade the release, setting `replicaCount` to `4`.
4. Roll the release back to revision 1.

Leave the release installed at revision 3. Write the output of `helm history frontend -n shop` to `/opt/cka/task4-history.txt` on `c1-cp-1`.

---

## Task 5 — Kustomize overlay

**Weight: 5% · Context: `cluster-2`**

A Kustomize base exists on `c2-cp-1` at `/opt/cka/kustomize/base`. It defines a Deployment named `catalog` with 1 replica using image `nginx:1.24`.

Create an overlay at `/opt/cka/kustomize/overlays/prod` that, without editing any file under `base/`:

- Deploys into namespace `prod` (the namespace already exists)
- Sets `replicas` to `4`
- Changes the image tag to `1.27`
- Adds the common label `tier=frontend` to all generated resources

Apply the overlay to the cluster.

---

## Task 6 — Custom Resource Definition

**Weight: 4% · Context: `cluster-2`**

Create a namespaced CustomResourceDefinition:

- Group: `stable.example.com`
- Version: `v1` (served and stored)
- Kind: `Backup`, plural `backups`, singular `backup`, short name `bk`
- Schema: `spec.schedule` (string, **required**) and `spec.retentionDays` (integer)

Then create a `Backup` named `nightly` in namespace `ops` with `schedule: "0 3 * * *"` and `retentionDays: 14`.

Confirm `kubectl get bk -n ops` returns it.

---

## Task 7 — Constrained scheduling

**Weight: 6% · Context: `cluster-1`**

Node `c1-node-2` carries the taint `hardware=gpu:NoSchedule` and the label `accelerator=nvidia`.

Create a Deployment named `trainer` in namespace `ml`:

- Image `busybox:1.36`, command `sleep 3600`
- 2 replicas
- Resource requests: `250m` CPU, `256Mi` memory; limits: `500m` CPU, `512Mi` memory
- Both replicas **must** land on `c1-node-2` and must not be schedulable onto any node lacking the `accelerator=nvidia` label

Use node affinity (not `nodeSelector`) for the placement constraint.

---

## Task 8 — Configuration injection

**Weight: 5% · Context: `cluster-1`**

In namespace `billing`:

1. Create a ConfigMap `billing-config` with `APP_ENV=production` and `LOG_LEVEL=debug`.
2. Create a Secret `billing-creds` with `DB_USER=billing` and `DB_PASS=Tr0ub4dor&3`.
3. Create a Pod `invoicer` using image `busybox:1.36` running `sleep 3600` that:
   - Loads **all** ConfigMap keys as environment variables
   - Exposes the Secret's `DB_USER` key as the environment variable `DATABASE_USER`
   - Mounts the whole Secret read-only at `/etc/billing`

---

## Task 9 — Rollout and rollback

**Weight: 4% · Context: `cluster-1`**

Deployment `storefront` in namespace `retail` is running `nginx:1.24`.

1. Set the deployment's update strategy to `RollingUpdate` with `maxSurge: 1` and `maxUnavailable: 0`.
2. Update the image to `nginx:1.27` and wait for the rollout to complete.
3. Update the image to `nginx:1.99-doesnotexist`. Observe the failure.
4. Roll back to the revision running `nginx:1.27` — **not** simply the previous revision.

Record the final revision number in `/opt/cka/task9-revision.txt` on `c1-cp-1`.

---

## Task 10 — Network policy

**Weight: 7% · Context: `cluster-2`**

Namespace `payments` contains pods labelled `app=ledger` (listening on TCP 8080), `role=frontend`, and `role=scanner`.

Create NetworkPolicies so that:

- All ingress to every pod in `payments` is denied by default.
- Pods labelled `app=ledger` accept ingress **only** from pods labelled `role=frontend` in the same namespace, and **only** on TCP port 8080.
- Egress is not restricted.

Verify: `role=frontend` can reach the ledger; `role=scanner` cannot.

---

## Task 11 — Services and endpoints

**Weight: 6% · Context: `cluster-2`**

In namespace `inventory` there is a Deployment `stock-api` with 3 replicas listening on container port `9090`.

1. Expose it with a ClusterIP Service named `stock-svc` on port `80`, targeting the container port by **name** (`http`), not by number. Add the port name to the deployment if it is missing.
2. Additionally expose it as a NodePort Service named `stock-nodeport` on port `80`, pinned to node port `31090`.
3. Confirm both Services have 3 ready endpoints.

Write the ClusterIP of `stock-svc` to `/opt/cka/task11-clusterip.txt` on `c1-cp-1` (your workstation — all answer files live there).

---

## Task 12 — Gateway API

**Weight: 7% · Context: `cluster-2`**

The Gateway API CRDs are installed and a GatewayClass named `cka-gc` exists.

In namespace `edge`:

1. Create a Gateway `edge-gw` using GatewayClass `cka-gc`, with a listener named `http` on protocol HTTP port 80, allowing routes from **all namespaces**.
2. Create an HTTPRoute `shop-route` in namespace `inventory` that attaches to `edge-gw`, matches hostname `shop.example.com`, and routes:
   - path prefix `/api` → Service `stock-svc` port 80
   - path prefix `/` → Service `stock-svc` port 80 with weight 100

Both resources must be accepted by the API server without validation errors.

---

## Task 13 — Bind a pending claim

**Weight: 5% · Context: `cluster-2`**

PersistentVolumeClaim `logs-pvc` in namespace `observability` is stuck in `Pending`. No dynamic provisioner is available.

Make the claim bind. Do not edit, delete or recreate the PVC.

---

## Task 14 — StorageClass and deferred binding

**Weight: 5% · Context: `cluster-2`**

1. Create a StorageClass named `local-delayed`:
   - provisioner `kubernetes.io/no-provisioner`
   - reclaim policy `Delete`
   - volume binding mode `WaitForFirstConsumer`
   - allow volume expansion
2. Create a 1Gi `ReadWriteOnce` PersistentVolume named `local-pv-a` backed by hostPath `/mnt/local-a` on `c2-node-1`, using StorageClass `local-delayed` and a node affinity term restricting it to `c2-node-1`.
3. Create PVC `app-data` in namespace `default` requesting 1Gi from `local-delayed`, then a Pod `consumer` (image `busybox:1.36`, `sleep 3600`) that mounts it at `/data`.

The PVC must move from `Pending` to `Bound` only once the Pod is scheduled.

---

## Task 15 — Recover a NotReady node

**Weight: 7% · Context: `cluster-1`**

Node `c1-node-1` reports `NotReady`. Diagnose the root cause from the node itself and bring it back to `Ready`.

Do not `kubeadm reset` the node, do not rejoin it, and do not reboot the droplet.

Write a one-line description of the root cause to `/opt/cka/task15-cause.txt` on `c1-cp-1`.

---

## Task 16 — Service with no endpoints

**Weight: 7% · Context: `cluster-1`**

In namespace `checkout`, Service `checkout-svc` is reachable but every request returns a connection error. The backing Deployment `checkout` is healthy and its pods are `Running`.

Fix the Service so it correctly load-balances to the `checkout` pods on the port the container actually listens on. Do not modify the Deployment.

Verify from a throwaway pod that `curl checkout-svc.checkout.svc.cluster.local` returns the nginx welcome page.

---

## Task 17 — CrashLoopBackOff and resource reporting

**Weight: 8% · Context: `cluster-1`**

**Part A.** Deployment `reporting` in namespace `analytics` is in `CrashLoopBackOff`. Find the cause using the container's output stream and fix it. The fix must be made to the ConfigMap or the Pod template — do not change the container image or command.

**Part B.** Once the cluster is stable, identify the pod consuming the most memory across all namespaces and write its name and namespace, in the format `<namespace>/<pod-name>`, to `/opt/cka/task17-topmem.txt` on `c1-cp-1`.

---

## Scoring

| Domain | Tasks | Weight |
|---|---|---|
| Cluster Architecture, Installation & Configuration | 2, 3, 4, 5, 6 | 25% |
| Workloads & Scheduling | 7, 8, 9 | 15% |
| Services & Networking | 10, 11, 12 | 20% |
| Storage | 13, 14 | 10% |
| Troubleshooting | 1, 15, 16, 17 | 30% |

Run `./ansible/grade.sh` from the repo root to score yourself automatically.

> **Note on etcd backup/restore:** it is deliberately absent. It was removed from the CKA
> curriculum in the 2025 refresh and is no longer an examinable competency. If you are
> studying from older material, that section is out of scope.
