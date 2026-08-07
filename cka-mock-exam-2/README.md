# CKA Mock Exam Lab

A 17-task, 2-hour CKA mock exam plus the Terraform and Ansible to provision two
real kubeadm clusters on DigitalOcean — deliberately broken in the specific ways
the exam asks you to fix.

```
exam/MOCK_EXAM.md     the paper
exam/ANSWER_KEY.md    solutions, with the trap in each task called out
terraform/            DigitalOcean droplets, VPC, firewall
ansible/              cluster build, exam setup, fault injection, grader
```

---

## What gets built

| Cluster | Nodes | Used for |
|---|---|---|
| `cluster-1` | `c1-cp-1`, `c1-node-1`, `c1-node-2` | RBAC, workloads, scheduling, node troubleshooting |
| `cluster-2` | `c2-cp-1`, `c2-node-1` | networking, storage, Helm/Kustomize, Gateway API |

- **Ubuntu 26.04 LTS** (Resolute Raccoon, released 23 April 2026)
- **kubeadm**-bootstrapped, containerd runtime, systemd cgroup driver
- **Calico** CNI — chosen deliberately: Flannel accepts NetworkPolicy objects and
  silently ignores them, which would make Task 10 appear to pass while enforcing
  nothing
- metrics-server, Helm, Gateway API CRDs and NGINX Gateway Fabric preinstalled
- `c1-cp-1` doubles as your exam workstation: it holds a merged kubeconfig with
  both clusters as the contexts `cluster-1` and `cluster-2`

**Cost: roughly $0.16/hour** for the default five droplets. `terraform destroy`
when you finish.

---

## Prerequisites

- Terraform ≥ 1.6
- Ansible ≥ 2.15 (`ansible-core`; no external collections required)
- A DigitalOcean API token with read/write scope
- An SSH key already uploaded to your DigitalOcean account
- `kubectl`, `jq` locally if you want to grade from your laptop

---

## Quick start

```bash
git clone <this repo> && cd cka-mock-exam

# 1. Infrastructure
cd terraform
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars              # token + ssh_key_name
terraform init
terraform apply                       # ~2 min

# 2. Clusters
cd ../ansible
ansible-playbook site.yml             # ~12-15 min
ansible-playbook exam-setup.yml       # ~2 min
ansible-playbook break.yml            # ~2 min

# 3. Sit the exam
ssh root@$(cd ../terraform && terraform output -raw ssh_workstation | awk '{print $2}' | cut -d@ -f2)
```

Terraform writes `ansible/inventory.ini` and, after `site.yml`, a merged
`./kubeconfig` you can use from your laptop:

```bash
export KUBECONFIG=$PWD/kubeconfig
kubectl config get-contexts     # cluster-1, cluster-2
```

Open `exam/MOCK_EXAM.md`, start a 2-hour timer, and don't open the answer key.

---

## Grading

```bash
scp ansible/grade.sh root@<c1-cp-1>:/root/
ssh root@<c1-cp-1> bash /root/grade.sh
```

It scores all 17 tasks against the live clusters, awards partial credit per
sub-check, and prints a weighted total against the 66% pass mark. Several tasks
write an answer to a file under `/opt/cka` on `c1-cp-1`; the grader reads those
too, so run it there rather than from your laptop.

---

## Re-arming individual tasks

Every fault is tagged, so you can retry one task without rebuilding anything:

```bash
cd ansible
ansible-playbook repair.yml -t crashloop    # reset to healthy
ansible-playbook break.yml  -t crashloop    # break it again
```

| Tag | Task | Fault |
|---|---|---|
| `apiserver` | 1 | `--client-ca-file` in the static pod manifest points at a missing file |
| `skew` | 3 | `c1-node-2` pinned to an older patch release |
| `pvc` | 13 | no PersistentVolume matches `logs-pvc` |
| `kubelet` | 15 | malformed YAML appended to `/var/lib/kubelet/config.yaml` |
| `endpoints` | 16 | Service selector *and* targetPort are both wrong |
| `crashloop` | 17 | ConfigMap key `app.config` vs the mount path `app.conf` |

`skew` is tagged `never`, so it only runs when named explicitly — the initial
version pin is applied during `site.yml`.

To reset the whole lab: `ansible-playbook repair.yml && ansible-playbook break.yml`.

---

## Version notes — read before you apply

**Ubuntu image slug.** `ubuntu_image` defaults to `ubuntu-26-04-x64`. DigitalOcean
publishes new LTS images on its own schedule and per-region, and direct upgrades
from 24.04 only open up at 26.04.1 in August 2026. Verify before applying:

```bash
doctl compute image list-distribution --public | grep -i ubuntu
```

If 26.04 is not available in your region, set `ubuntu_image = "ubuntu-24-04-x64"`.
Everything else works unchanged — `pkgs.k8s.io` is a distribution-agnostic deb
repository.

**Kubernetes version.** `kube_stream` is `1.34`, matching the study guide this
exam was written against. Kubernetes ships roughly three minor releases a year
and the CKA tracks within 4–8 weeks of each, so the live exam may well be on a
later minor by the time you read this. Nothing here hardcodes a patch version —
the playbook resolves the newest published patch in the stream at build time — so
bumping `kube_stream` in `ansible/group_vars/all.yml` is usually the only change
needed. Confirm the current exam version on the
[Linux Foundation CKA page](https://training.linuxfoundation.org/certification/certified-kubernetes-administrator-cka/)
before you rely on it.

**The version-skew task.** By default Task 3 is a *patch*-level upgrade within
one minor stream. This exercises the identical `kubeadm upgrade node` procedure
with none of the risk: a true minor-version skew means a 1.33 kubelet consuming
a KubeletConfiguration written by 1.34 kubeadm, which can fail to parse on
unknown fields. If you want the harder variant, set `kube_skew_stream: "1.33"`
and be prepared to repair the node manually.

**etcd backup and restore is deliberately absent.** It was removed from the CKA
curriculum in the 2025 refresh. If your study material still covers it, that
section is out of scope for the current exam.

---

## Security

The firewall restricts SSH, port 6443 and the NodePort range to the public /32
Terraform detects for the machine running `apply`. These clusters run
intentionally broken control plane components with intentionally permissive RBAC —
do not widen `allowed_ssh_cidrs` to `0.0.0.0/0`, and destroy the lab when you
are finished rather than leaving it running.

If your public IP rotates, re-run `terraform apply` to refresh the rule, or pin
`allowed_ssh_cidrs` explicitly in `terraform.tfvars`.

---

## Lab troubleshooting

**`site.yml` fails at "Wait for the control plane node to report Ready".**
Calico is still pulling. Re-run the playbook; it is idempotent.

**Workers won't join.** Bootstrap tokens are created with a 4-hour TTL. If you
resume the build much later, re-run `site.yml` — it mints a fresh token.

**NGINX Gateway Fabric fails to install.** Task 12 still grades correctly: the
Gateway and HTTPRoute validate against the API server either way. Set
`install_gateway_controller: false` in `group_vars/all.yml` to skip it.

**`kubectl top` returns nothing.** metrics-server needs 30–60 seconds after
install to populate. If it persists, check the deployment picked up
`--kubelet-insecure-tls`.

**Everything is on fire.** `terraform destroy && terraform apply` and start over;
a full rebuild is about 20 minutes.

---

## Teardown

```bash
cd terraform && terraform destroy
```
