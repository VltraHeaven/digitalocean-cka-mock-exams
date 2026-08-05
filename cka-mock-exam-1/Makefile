.PHONY: help infra cluster setup arm exam reset grade destroy all

TF := terraform -chdir=terraform
AP := ansible-playbook

help:
	@echo "make all      - infra + cluster + setup + arm  (full build, ~20 min)"
	@echo "make infra    - terraform apply"
	@echo "make cluster  - build both kubeadm clusters"
	@echo "make setup    - create the exam prerequisites"
	@echo "make arm      - inject the faults"
	@echo "make reset    - repair everything, then re-arm"
	@echo "make grade    - run the grader on c1-cp-1"
	@echo "make destroy  - tear down all DigitalOcean resources"

all: infra cluster setup arm

infra:
	$(TF) init -input=false
	$(TF) apply -auto-approve

cluster:
	cd ansible && $(AP) site.yml

setup:
	cd ansible && $(AP) exam-setup.yml

arm:
	cd ansible && $(AP) break.yml

reset:
	cd ansible && $(AP) repair.yml && $(AP) break.yml

grade:
	@IP=$$($(TF) output -json cluster1_control_plane | python3 -c 'import json,sys;print(list(json.load(sys.stdin).values())[0])'); \
	scp -o StrictHostKeyChecking=no ansible/grade.sh root@$$IP:/root/grade.sh; \
	ssh -o StrictHostKeyChecking=no root@$$IP bash /root/grade.sh

destroy:
	$(TF) destroy -auto-approve
