#!/usr/bin/env bash
set -uo pipefail

export KUBECONFIG="${KUBECONFIG:-/root/.kube/config}"
ANSWER_DIR="${ANSWER_DIR:-/opt/cka}"

K1="kubectl --context cluster-1-admin@cluster-1"
K2="kubectl --context cluster-2-admin@cluster-2"

TOTAL=0
EARNED=0
declare -a REPORT

c() { printf '\033[%sm%s\033[0m' "$1" "$2"; }

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

echo
echo "  CKA Mock Exam 2 — grading $(date -u '+%Y-%m-%d %H:%M UTC')"
echo "  ============================================================"
echo

# --- Task 1: cluster-1 Scheduler -------------------------------------------
t1() {
  [ "$($K1 get pods -n kube-system -l component=kube-scheduler -o jsonpath='{.items[0].status.phase}' 2>/dev/null)" = "Running" ]
}
score 8 "T1  cluster-1 scheduler restored and Running" t1

# --- Task 2: Developer Permissions -----------------------------------------
t2() {
  local S=system:serviceaccount:development:dev-sa n=0
  $K1 -n development get sa dev-sa >/dev/null 2>&1 && n=$((n+1))
  [ "$($K1 auth can-i create deployments --as=$S -n development 2>/dev/null)" = "yes" ] && n=$((n+1))
  [ "$($K1 auth can-i create services    --as=$S -n development 2>/dev/null)" = "yes" ] && n=$((n+1))
  [ "$($K1 auth can-i get secrets        --as=$S -n development 2>/dev/null)" = "yes" ] && n=$((n+1))
  [ "$($K1 auth can-i delete secrets     --as=$S -n development 2>/dev/null)" = "no"  ] && n=$((n+1))
  echo "$n"
}
partial 5 "T2  developer permissions for dev-sa" "$(t2)" 5

# --- Task 3: Upgrade Control Plane -----------------------------------------
t3() {
  local ver
  ver=$($K2 get node c2-cp-1 -o jsonpath='{.status.nodeInfo.kubeletVersion}' 2>/dev/null)
  [[ "$ver" == v1.34.* ]]
}
score 7 "T3  c2-cp-1 upgraded to v1.34.x" t3

# --- Task 4: Static Pod ----------------------------------------------------
t4() {
  $K1 get pod monitor-c1-node-2 -o jsonpath='{.status.phase}' 2>/dev/null | grep -q Running
}
score 4 "T4  static pod monitor on c1-node-2" t4

# --- Task 5: Sidecar Container ---------------------------------------------
t5() {
  local n=0
  [ "$($K1 -n apps get deploy legacy-app -o jsonpath='{range .spec.template.spec.containers[*]}{.name}{" "}{end}' 2>/dev/null | grep -c 'log-tailer')" -eq 1 ] && n=$((n+1))
  [ "$($K1 -n apps get deploy legacy-app -o jsonpath='{.spec.template.spec.volumes[0].emptyDir}' 2>/dev/null | grep -c '{}')" -eq 1 ] && n=$((n+1))
  echo "$n"
}
partial 5 "T5  sidecar log-tailer added to legacy-app" "$(t5)" 2

# --- Task 6: Ingress Resource ----------------------------------------------
t6() {
  local n=0
  [ "$($K1 -n production get ingress front-ingress -o jsonpath='{.spec.rules[0].host}' 2>/dev/null)" = "app.example.com" ] && n=$((n+1))
  [ "$($K1 -n production get ingress front-ingress -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.name}' 2>/dev/null)" = "front-svc" ] && n=$((n+1))
  echo "$n"
}
partial 7 "T6  front-ingress created correctly" "$(t6)" 2

# --- Task 7: Taints and Tolerations ----------------------------------------
t7() {
  local n=0
  $K2 get node c2-node-1 -o jsonpath='{.spec.taints}' 2>/dev/null | grep -q gold && n=$((n+1))
  [ "$($K2 get pod gold-pod -o jsonpath='{.status.phase}' 2>/dev/null)" = "Running" ] && n=$((n+1))
  [ "$($K2 get pod gold-pod -o jsonpath='{.spec.nodeName}' 2>/dev/null)" = "c2-node-1" ] && n=$((n+1))
  echo "$n"
}
partial 6 "T7  gold-pod scheduled on tainted c2-node-1" "$(t7)" 3

# --- Task 8: PV and PVC ----------------------------------------------------
t8() {
  local n=0
  [ "$($K1 get pv manual-pv -o jsonpath='{.status.phase}' 2>/dev/null)" = "Bound" ] && n=$((n+1))
  [ "$($K1 get pvc manual-pvc -o jsonpath='{.status.phase}' 2>/dev/null)" = "Bound" ] && n=$((n+1))
  [ "$($K1 get pv manual-pv -o jsonpath='{.spec.capacity.storage}' 2>/dev/null)" = "2Gi" ] && n=$((n+1))
  echo "$n"
}
partial 5 "T8  manual-pv and manual-pvc bound" "$(t8)" 3

# --- Task 9: Kubelet Troubleshooting ---------------------------------------
t9() {
  [ "$($K2 get node c2-node-1 -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" = "True" ]
}
score 7 "T9  c2-node-1 recovered to Ready" t9

# --- Task 10: ExternalName Service -----------------------------------------
t10() {
  [ "$($K2 -n legacy get svc db-external -o jsonpath='{.spec.externalName}' 2>/dev/null)" = "database.internal.example.com" ]
}
score 5 "T10 externalName service created" t10

# --- Task 11: Egress Network Policy ----------------------------------------
t11() {
  local n=0
  [ "$($K2 -n restricted get netpol egress-lock -o jsonpath='{.spec.policyTypes[0]}' 2>/dev/null)" = "Egress" ] && n=$((n+1))
  [ "$($K2 -n restricted get netpol egress-lock -o jsonpath='{.spec.egress[0].to[0].ipBlock.cidr}' 2>/dev/null)" = "10.10.10.10/32" ] && n=$((n+1))
  echo "$n"
}
partial 8 "T11 egress network policy egress-lock" "$(t11)" 2

# --- Task 12: ConfigMap and Secret -----------------------------------------
t12() {
  local n=0
  [ "$($K1 -n config-env get pod app-runner -o jsonpath='{.spec.containers[0].env[0].name}' 2>/dev/null)" = "APP_THEME" ] && n=$((n+1))
  [ "$($K1 -n config-env get pod app-runner -o jsonpath='{.spec.volumes[0].secret.secretName}' 2>/dev/null)" = "app-creds" ] && n=$((n+1))
  echo "$n"
}
partial 4 "T12 app-runner consumes ConfigMap and Secret" "$(t12)" 2

# --- Task 13: HPA ----------------------------------------------------------
t13() {
  local n=0
  [ "$($K2 -n scaling get hpa cpu-load -o jsonpath='{.spec.maxReplicas}' 2>/dev/null)" = "5" ] && n=$((n+1))
  [ "$($K2 -n scaling get hpa cpu-load -o jsonpath='{.spec.targetCPUUtilizationPercentage}' 2>/dev/null)" = "60" ] && n=$((n+1))
  echo "$n"
}
partial 5 "T13 HPA created for cpu-load" "$(t13)" 2

# --- Task 14: ClusterRole --------------------------------------------------
t14() {
  local n=0
  $K1 get clusterrole event-reader >/dev/null 2>&1 && n=$((n+1))
  $K1 get clusterrolebinding alice-event-access >/dev/null 2>&1 && n=$((n+1))
  echo "$n"
}
partial 5 "T14 event-reader ClusterRole and binding" "$(t14)" 2

# --- Task 15: Service Port Mismatch ----------------------------------------
t15() {
  [ "$($K2 -n api get svc backend-svc -o jsonpath='{.spec.ports[0].targetPort}' 2>/dev/null)" = "9090" ]
}
score 7 "T15 backend-svc targeting correct port" t15

# --- Task 16: StorageClass -------------------------------------------------
t16() {
  [ "$($K1 get sc archive-storage -o jsonpath='{.reclaimPolicy}' 2>/dev/null)" = "Retain" ]
}
score 4 "T16 archive-storage StorageClass with Retain policy" t16

# --- Task 17: CrashLoop Fix ------------------------------------------------
t17() {
  [ "$($K1 -n ops get deploy data-worker -o jsonpath='{.status.readyReplicas}' 2>/dev/null)" = "1" ]
}
score 8 "T17 data-worker recovered to Running" t17

echo
printf '%s\n' "${REPORT[@]}"
echo
echo "  ============================================================"
PCT=$(( TOTAL > 0 ? EARNED * 100 / TOTAL : 0 ))
printf "  Score: %d / %d  (%d%%)   " "$EARNED" "$TOTAL" "$PCT"
if [ "$PCT" -ge 66 ]; then c '1;32' "PASS"; else c '1;31' "FAIL — 66% required"; fi
echo
