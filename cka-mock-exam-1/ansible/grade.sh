#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# CKA mock exam grader
#
# Run ON c1-cp-1 as root, where /root/.kube/config holds both contexts:
#     scp ansible/grade.sh root@<c1-cp-1>:/root/ && ssh root@<c1-cp-1> bash /root/grade.sh
#
# Or from your laptop with the merged kubeconfig, though the file-based checks
# (Tasks 4, 9, 11, 15, 17B) will report as unverifiable:
#     KUBECONFIG=./kubeconfig ./grade.sh
# ---------------------------------------------------------------------------
set -uo pipefail

export KUBECONFIG="${KUBECONFIG:-/root/.kube/config}"
ANSWER_DIR="${ANSWER_DIR:-/opt/cka}"

K1="kubectl --context cluster-1-admin@cluster-1"
K2="kubectl --context cluster-2-admin@cluster-2"

TOTAL=0
EARNED=0
declare -a REPORT

c() { printf '\033[%sm%s\033[0m' "$1" "$2"; }

# score <weight> <label> <command...>
score() {
  local weight=$1 label=$2; shift 2
  TOTAL=$(( TOTAL + weight ))
  if "$@" >/dev/null 2>&1; then
    EARNED=$(( EARNED + weight ))
    REPORT+=("$(c '1;32' 'PASS')  ${weight}%  ${label}")
  else
    REPORT+=("$(c '1;31' 'FAIL')  ${weight}%  ${label}")
  fi
}

# partial <weight> <label> <n_passed_expr> <n_total>
partial() {
  local weight=$1 label=$2 got=$3 max=$4
  TOTAL=$(( TOTAL + weight ))
  local pts=$(( weight * got / max ))
  EARNED=$(( EARNED + pts ))
  if [ "$got" -eq "$max" ]; then
    REPORT+=("$(c '1;32' 'PASS')  ${pts}/${weight}%  ${label}")
  elif [ "$pts" -gt 0 ]; then
    REPORT+=("$(c '1;33' 'PART')  ${pts}/${weight}%  ${label} (${got}/${max} checks)")
  else
    REPORT+=("$(c '1;31' 'FAIL')  0/${weight}%  ${label}")
  fi
}

jp() { $1 get "${@:2}" 2>/dev/null; }
ok()  { [ "$1" = "$2" ]; }
has() { grep -q "$1" <<<"$2"; }

echo
echo "  CKA Mock Exam — grading $(date -u '+%Y-%m-%d %H:%M UTC')"
echo "  ============================================================"
echo

# --- Task 1: cluster-2 API server ------------------------------------------
t1() {
  local ready
  ready=$($K2 get nodes -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' 2>/dev/null | grep -c '^True$')
  [ "${ready:-0}" -ge 2 ]
}
score 8 "T1  cluster-2 API server restored, all nodes Ready" t1

# --- Task 2: RBAC ----------------------------------------------------------
t2() {
  local S=system:serviceaccount:build:ci-bot n=0
  $K1 -n build get sa ci-bot >/dev/null 2>&1 && n=$((n+1))
  [ "$($K1 auth can-i create pods      --as=$S -n build   2>/dev/null)" = "yes" ] && n=$((n+1))
  [ "$($K1 auth can-i list pods        --as=$S -n build   2>/dev/null)" = "yes" ] && n=$((n+1))
  [ "$($K1 auth can-i create pods/exec --as=$S -n build   2>/dev/null)" = "yes" ] && n=$((n+1))
  [ "$($K1 auth can-i delete pods      --as=$S -n build   2>/dev/null)" = "no"  ] && n=$((n+1))
  [ "$($K1 auth can-i list pods        --as=$S -n default 2>/dev/null)" = "no"  ] && n=$((n+1))
  echo "$n"
}
partial 5 "T2  scoped RBAC for ci-bot" "$(t2)" 6

# --- Task 3: node upgrade --------------------------------------------------
t3() {
  local n=0 versions unsched
  versions=$($K1 get nodes -o jsonpath='{range .items[*]}{.status.nodeInfo.kubeletVersion}{"\n"}{end}' 2>/dev/null | sort -u | wc -l)
  [ "$versions" = "1" ] && n=$((n+1))
  unsched=$($K1 get node c1-node-2 -o jsonpath='{.spec.unschedulable}' 2>/dev/null)
  [ -z "$unsched" ] && n=$((n+1))
  [ "$($K1 get node c1-node-2 -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" = "True" ] && n=$((n+1))
  echo "$n"
}
partial 7 "T3  c1-node-2 upgraded, uncordoned and Ready" "$(t3)" 3

# --- Task 4: Helm ----------------------------------------------------------
t4() {
  local n=0 rev
  helm status frontend -n shop >/dev/null 2>&1 && n=$((n+1))
  rev=$(helm list -n shop -o json 2>/dev/null | jq -r '.[]|select(.name=="frontend")|.revision')
  [ "${rev:-0}" -ge 3 ] 2>/dev/null && n=$((n+1))
  [ "$($K1 -n shop get deploy -o jsonpath='{.items[0].spec.replicas}' 2>/dev/null)" = "2" ] && n=$((n+1))
  [ -s "$ANSWER_DIR/task4-history.txt" ] && n=$((n+1))
  echo "$n"
}
partial 4 "T4  Helm install / upgrade / rollback" "$(t4)" 4

# --- Task 5: Kustomize -----------------------------------------------------
t5() {
  local n=0 img
  $K2 -n prod get deploy catalog >/dev/null 2>&1 && n=$((n+1))
  [ "$($K2 -n prod get deploy catalog -o jsonpath='{.spec.replicas}' 2>/dev/null)" = "4" ] && n=$((n+1))
  img=$($K2 -n prod get deploy catalog -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
  [[ "$img" == *:1.27 ]] && n=$((n+1))
  [ "$($K2 -n prod get deploy catalog -o jsonpath='{.metadata.labels.tier}' 2>/dev/null)" = "frontend" ] && n=$((n+1))
  echo "$n"
}
partial 5 "T5  Kustomize prod overlay applied" "$(t5)" 4

# --- Task 6: CRD -----------------------------------------------------------
t6() {
  local n=0
  $K2 get crd backups.stable.example.com >/dev/null 2>&1 && n=$((n+1))
  [ "$($K2 get crd backups.stable.example.com -o jsonpath='{.spec.scope}' 2>/dev/null)" = "Namespaced" ] && n=$((n+1))
  [ "$($K2 -n ops get backups.stable.example.com nightly -o jsonpath='{.spec.schedule}' 2>/dev/null)" = "0 3 * * *" ] && n=$((n+1))
  [ "$($K2 -n ops get backups.stable.example.com nightly -o jsonpath='{.spec.retentionDays}' 2>/dev/null)" = "14" ] && n=$((n+1))
  echo "$n"
}
partial 4 "T6  Backup CRD and nightly resource" "$(t6)" 4

# --- Task 7: scheduling ----------------------------------------------------
t7() {
  local n=0 nodes
  [ "$($K1 -n ml get deploy trainer -o jsonpath='{.status.readyReplicas}' 2>/dev/null)" = "2" ] && n=$((n+1))
  nodes=$($K1 -n ml get pods -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' 2>/dev/null | sort -u)
  [ "$nodes" = "c1-node-2" ] && n=$((n+1))
  $K1 -n ml get deploy trainer -o jsonpath='{.spec.template.spec.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution}' 2>/dev/null | grep -q accelerator && n=$((n+1))
  [ "$($K1 -n ml get deploy trainer -o jsonpath='{.spec.template.spec.containers[0].resources.requests.cpu}' 2>/dev/null)" = "250m" ] && n=$((n+1))
  [ "$($K1 -n ml get deploy trainer -o jsonpath='{.spec.template.spec.containers[0].resources.limits.memory}' 2>/dev/null)" = "512Mi" ] && n=$((n+1))
  echo "$n"
}
partial 6 "T7  trainer pinned to the GPU node with affinity + toleration" "$(t7)" 5

# --- Task 8: ConfigMap and Secret ------------------------------------------
t8() {
  local n=0 env
  env=$($K1 -n billing get pod invoicer -o json 2>/dev/null)
  jq -e '.spec.containers[0].envFrom[]?|select(.configMapRef.name=="billing-config")' <<<"$env" >/dev/null 2>&1 && n=$((n+1))
  jq -e '.spec.containers[0].env[]?|select(.name=="DATABASE_USER" and .valueFrom.secretKeyRef.key=="DB_USER")' <<<"$env" >/dev/null 2>&1 && n=$((n+1))
  jq -e '.spec.volumes[]?|select(.secret.secretName=="billing-creds")' <<<"$env" >/dev/null 2>&1 && n=$((n+1))
  jq -e '.spec.containers[0].volumeMounts[]?|select(.mountPath=="/etc/billing" and .readOnly==true)' <<<"$env" >/dev/null 2>&1 && n=$((n+1))
  echo "$n"
}
partial 5 "T8  invoicer consumes ConfigMap and Secret correctly" "$(t8)" 4

# --- Task 9: rollout -------------------------------------------------------
t9() {
  local n=0 img
  img=$($K1 -n retail get deploy storefront -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
  [ "$img" = "nginx:1.27" ] && n=$((n+1))
  [ "$($K1 -n retail get deploy storefront -o jsonpath='{.spec.strategy.rollingUpdate.maxSurge}' 2>/dev/null)" = "1" ] && n=$((n+1))
  [ "$($K1 -n retail get deploy storefront -o jsonpath='{.spec.strategy.rollingUpdate.maxUnavailable}' 2>/dev/null)" = "0" ] && n=$((n+1))
  [ -s "$ANSWER_DIR/task9-revision.txt" ] && n=$((n+1))
  echo "$n"
}
partial 4 "T9  storefront rolled back to nginx:1.27" "$(t9)" 4

# --- Task 10: NetworkPolicy ------------------------------------------------
t10() {
  local n=0 fe sc
  [ "$($K2 -n payments get netpol -o json 2>/dev/null | jq '[.items[]|select(.spec.podSelector=={})]|length')" -ge 1 ] && n=$((n+1))
  [ "$($K2 -n payments get netpol -o json 2>/dev/null | jq '[.items[]|select(.spec.podSelector.matchLabels.app=="ledger")]|length')" -ge 1 ] && n=$((n+1))
  fe=$($K2 -n payments exec deploy/frontend -- wget -qO- --timeout=4 http://ledger:8080 2>/dev/null)
  [[ "$fe" == *"ledger ok"* ]] && n=$((n+1))
  sc=$($K2 -n payments exec deploy/scanner -- wget -qO- --timeout=4 http://ledger:8080 2>/dev/null)
  [ -z "$sc" ] && n=$((n+1))
  echo "$n"
}
partial 7 "T10 ledger reachable from frontend only" "$(t10)" 4

# --- Task 11: Services -----------------------------------------------------
t11() {
  local n=0 eps
  [ "$($K2 -n inventory get svc stock-svc -o jsonpath='{.spec.ports[0].targetPort}' 2>/dev/null)" = "http" ] && n=$((n+1))
  eps=$($K2 -n inventory get endpointslices -l kubernetes.io/service-name=stock-svc -o json 2>/dev/null | jq '[.items[].endpoints[]?]|length')
  [ "${eps:-0}" -eq 3 ] && n=$((n+1))
  [ "$($K2 -n inventory get svc stock-nodeport -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)" = "31090" ] && n=$((n+1))
  [ -s "$ANSWER_DIR/task11-clusterip.txt" ] && n=$((n+1))
  echo "$n"
}
partial 6 "T11 stock-svc and stock-nodeport with 3 endpoints" "$(t11)" 4

# --- Task 12: Gateway API --------------------------------------------------
t12() {
  local n=0 gw rt
  gw=$($K2 -n edge get gateway edge-gw -o json 2>/dev/null)
  [ -n "$gw" ] && n=$((n+1))
  jq -e '.spec.listeners[]|select(.name=="http" and .port==80 and .protocol=="HTTP" and .allowedRoutes.namespaces.from=="All")' <<<"$gw" >/dev/null 2>&1 && n=$((n+1))
  rt=$($K2 -n inventory get httproute shop-route -o json 2>/dev/null)
  jq -e '.spec.parentRefs[]|select(.name=="edge-gw" and .namespace=="edge")' <<<"$rt" >/dev/null 2>&1 && n=$((n+1))
  jq -e '.spec.hostnames|index("shop.example.com")' <<<"$rt" >/dev/null 2>&1 && n=$((n+1))
  [ "$(jq '[.spec.rules[]]|length' <<<"$rt" 2>/dev/null)" -ge 2 ] && n=$((n+1))
  echo "$n"
}
partial 7 "T12 Gateway edge-gw and cross-namespace HTTPRoute" "$(t12)" 5

# --- Task 13: PVC binding --------------------------------------------------
t13() { [ "$($K2 -n observability get pvc logs-pvc -o jsonpath='{.status.phase}' 2>/dev/null)" = "Bound" ]; }
score 5 "T13 logs-pvc is Bound" t13

# --- Task 14: StorageClass and local PV ------------------------------------
t14() {
  local n=0 sc
  sc=$($K2 get sc local-delayed -o json 2>/dev/null)
  jq -e 'select(.volumeBindingMode=="WaitForFirstConsumer" and .allowVolumeExpansion==true)' <<<"$sc" >/dev/null 2>&1 && n=$((n+1))
  $K2 get pv local-pv-a -o jsonpath='{.spec.nodeAffinity}' 2>/dev/null | grep -q c2-node-1 && n=$((n+1))
  [ "$($K2 -n default get pvc app-data -o jsonpath='{.status.phase}' 2>/dev/null)" = "Bound" ] && n=$((n+1))
  [ "$($K2 -n default get pod consumer -o jsonpath='{.status.phase}' 2>/dev/null)" = "Running" ] && n=$((n+1))
  echo "$n"
}
partial 5 "T14 local-delayed StorageClass bound to a running consumer" "$(t14)" 4

# --- Task 15: NotReady node ------------------------------------------------
t15() {
  local n=0
  [ "$($K1 get node c1-node-1 -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" = "True" ] && n=$((n+1))
  [ -z "$($K1 get node c1-node-1 -o jsonpath='{.spec.unschedulable}' 2>/dev/null)" ] && n=$((n+1))
  [ -s "$ANSWER_DIR/task15-cause.txt" ] && n=$((n+1))
  echo "$n"
}
partial 7 "T15 c1-node-1 recovered to Ready" "$(t15)" 3

# --- Task 16: Service endpoints --------------------------------------------
t16() {
  local n=0 eps body
  eps=$($K1 -n checkout get endpointslices -l kubernetes.io/service-name=checkout-svc -o json 2>/dev/null | jq '[.items[].endpoints[]?]|length')
  [ "${eps:-0}" -ge 2 ] && n=$((n+1))
  [ "$($K1 -n checkout get svc checkout-svc -o jsonpath='{.spec.ports[0].targetPort}' 2>/dev/null)" = "80" ] && n=$((n+1))
  body=$($K1 -n checkout run grader-probe-$$ --rm -i --restart=Never --timeout=60s \
           --image=busybox:1.36 -- wget -qO- --timeout=5 http://checkout-svc 2>/dev/null)
  [[ "$body" == *"Welcome to nginx"* ]] && n=$((n+1))
  echo "$n"
}
partial 7 "T16 checkout-svc load-balances to its pods" "$(t16)" 3

# --- Task 17: CrashLoop + top ----------------------------------------------
t17() {
  local n=0 restarts recorded actual
  [ "$($K1 -n analytics get deploy reporting -o jsonpath='{.status.readyReplicas}' 2>/dev/null)" = "1" ] && n=$((n+1))
  restarts=$($K1 -n analytics get pods -o jsonpath='{.items[0].status.containerStatuses[0].restartCount}' 2>/dev/null)
  [ "${restarts:-99}" -le 2 ] && n=$((n+1))
  if [ -s "$ANSWER_DIR/task17-topmem.txt" ]; then
    n=$((n+1))
    recorded=$(tr -d '[:space:]' < "$ANSWER_DIR/task17-topmem.txt")
    actual=$($K1 top pods -A --no-headers --sort-by=memory 2>/dev/null | head -1 | awk '{print $1"/"$2}')
    [ -n "$actual" ] && [ "$recorded" = "$actual" ] && n=$((n+1))
  fi
  echo "$n"
}
partial 8 "T17 reporting healthy and top-memory pod identified" "$(t17)" 4

# ---------------------------------------------------------------------------
echo
printf '%s\n' "${REPORT[@]}"
echo
echo "  ============================================================"
PCT=$(( TOTAL > 0 ? EARNED * 100 / TOTAL : 0 ))
printf "  Score: %d / %d  (%d%%)   " "$EARNED" "$TOTAL" "$PCT"
if [ "$PCT" -ge 66 ]; then c '1;32' "PASS"; else c '1;31' "FAIL — 66% required"; fi
echo; echo
echo "  Review solutions in exam/ANSWER_KEY.md"
echo "  Reset a task:  ansible-playbook repair.yml -t <tag> && ansible-playbook break.yml -t <tag>"
echo
