SHELL := /bin/bash

.EXPORT_ALL_VARIABLES:

KUBECONFIG = /tmp/notebook-demo

.PHONY: all
all: bootstrap

.PHONY: login
login:
	rm -f $(KUBECONFIG)
	$(MAKE) $(KUBECONFIG)

$(KUBECONFIG): creds.env
	@source creds.env; oc login -u "$$USER" -p "$$PASSWORD" "$$CLUSTER"

.PHONY: bootstrap
bootstrap: $(KUBECONFIG)
	oc apply -k bootstrap/ || \
		while [ "$$(oc get subscription.operators -n openshift-operators openshift-gitops-operator -ojsonpath='{.status.state}')" != "AtLatestKnown" ]; do sleep 5; done; oc apply -k bootstrap/ || \
		while ! oc get namespace openshift-gitops; do sleep 5; done; oc apply -k bootstrap/
